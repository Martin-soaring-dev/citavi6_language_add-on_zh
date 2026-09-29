# -*- coding: utf-8 -*-
"""
通过 translate-mcp-server 的 MCP 接口批量翻译 translations/*.tsv。

- 以 MCP HTTP SSE 协议连接本地 translate-mcp-server(JSON-RPC tools/call "translate");
- 多会话并发,每个会话一条 SSE 连接,逐个请求;
- 结果缓存到 reference/mt-cache.json(以英文原文为键),可断点续传;
- 校验 {n} 占位符一致性,不一致则丢弃;
- 回填 translations/*.tsv 第 3 列。

用法:
    python tools/mcp_translate.py --repo <仓库根> [--workers 4] [--port 38089]
                                  [--limit N] [--only SUBSTR] [--target zh-CN]
"""
import argparse
import io
import json
import os
import queue
import re
import sys
import threading
import time

import requests

PLACEHOLDER_RE = re.compile(r"\{[0-9]+\}")


def placeholder_sig(s):
    return ",".join(sorted(PLACEHOLDER_RE.findall(s or "")))


def iter_sse(resp):
    """从 SSE 流中逐条产出 (event, data)。"""
    event = None
    data_lines = []
    for raw in resp.iter_lines(decode_unicode=True):
        if raw is None:
            continue
        line = raw
        if line == "":
            if data_lines:
                yield event, "\n".join(data_lines)
            event = None
            data_lines = []
            continue
        if line.startswith(":"):
            continue
        if line.startswith("event:"):
            event = line[6:].strip()
        elif line.startswith("data:"):
            data_lines.append(line[5:].lstrip())


class McpSession:
    def __init__(self, port, timeout=120):
        self.port = port
        self.timeout = timeout
        self.sess = requests.Session()
        self.resp = self.sess.get(
            "http://localhost:%d/sse" % port,
            stream=True,
            headers={"Accept": "text/event-stream"},
            timeout=(10, timeout),
        )
        self.resp.raise_for_status()
        self.it = iter_sse(self.resp)
        self.endpoint = None
        for ev, data in self.it:
            if ev == "endpoint":
                self.endpoint = data
                break
        if not self.endpoint:
            raise RuntimeError("未收到 endpoint 事件")
        self.url = "http://localhost:%d%s" % (port, self.endpoint)
        self._id = 0
        self._post({
            "jsonrpc": "2.0", "id": self._next_id(), "method": "initialize",
            "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                       "clientInfo": {"name": "citavi-zh-mt", "version": "1.0"}},
        })
        self._read_message()
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

    def _next_id(self):
        self._id += 1
        return self._id

    def _post(self, payload):
        r = self.sess.post(self.url, json=payload, timeout=(10, self.timeout))
        r.raise_for_status()

    def _read_message(self):
        for ev, data in self.it:
            if ev == "message":
                return json.loads(data)
        raise RuntimeError("SSE 流结束")

    def translate(self, text, target="zh-CN"):
        rid = self._next_id()
        self._post({
            "jsonrpc": "2.0", "id": rid, "method": "tools/call",
            "params": {"name": "translate", "arguments": {"text": text, "target": target}},
        })
        while True:
            msg = self._read_message()
            if msg.get("id") != rid:
                continue
            if "error" in msg:
                raise RuntimeError(msg["error"].get("message", "unknown error"))
            content = msg.get("result", {}).get("content", [])
            if not content:
                raise RuntimeError("空响应")
            payload = json.loads(content[0]["text"])
            return payload.get("targetText", "")

    def close(self):
        try:
            self.resp.close()
        except Exception:
            pass


def worker(items, out, lock, port, target, retries, delay, stats):
    try:
        session = McpSession(port)
    except Exception as e:
        with lock:
            print("[worker] 会话建立失败: %s" % e, flush=True)
        return
    for en in items:
        zh = None
        for attempt in range(retries):
            try:
                zh = session.translate(en, target)
                break
            except Exception as e:
                time.sleep(min(8, 1 + attempt * 2))
                if attempt == retries - 1:
                    with lock:
                        stats["fail"] += 1
                        print("[worker] 失败: %r (%s)" % (en[:60], e), flush=True)
        if zh is None:
            continue
        zh = zh.strip()
        if not zh:
            with lock:
                stats["fail"] += 1
            continue
        if placeholder_sig(en) != placeholder_sig(zh):
            with lock:
                stats["fail"] += 1
                print("[worker] 占位符不一致,丢弃: %r" % en[:60], flush=True)
            continue
        with lock:
            out[en] = zh
            stats["done"] += 1
            if stats["done"] % 25 == 0:
                save_cache(out, stats["cache_path"])
                print("  进度 %d/%d  失败 %d" % (stats["done"], stats["total"], stats["fail"]), flush=True)
        if delay:
            time.sleep(delay)
    session.close()


def save_cache(cache, path):
    tmp = path + ".tmp"
    with io.open(tmp, "w", encoding="utf-8") as f:
        json.dump(cache, f, ensure_ascii=False, indent=0, sort_keys=True)
    os.replace(tmp, path)


def is_skippable(en):
    """内部数据(非 UI 文本)不应翻译,例如多语言占位符/文件过滤器:
        im Druck|in Vorbereitung|forthcoming|...
        BibTeX Files (*.bib; *.txt)|*.bib;*.txt|All Files (*.*)|*.*
    注意:含 `{n:...|...}` 的是 .NET SmartFormat 单复数条件,属于界面文本,必须翻译。"""
    return ("|" in en) and not re.search(r"\{\d+:", en)


def scan_pending(translations_dir, cache, only, limit, include_pipes=False):
    pending = []
    skipped = 0
    seen = set()
    for root, _dirs, files in os.walk(translations_dir):
        for name in sorted(files):
            if not name.endswith(".tsv"):
                continue
            path = os.path.join(root, name)
            if only and only not in path:
                continue
            with io.open(path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.rstrip("\r\n")
                    if not line:
                        continue
                    parts = line.split("\t")
                    if len(parts) < 3:
                        continue
                    en = parts[1]
                    if not en or parts[2]:
                        continue
                    if en in cache or en in seen:
                        continue
                    if not re.search(r"[A-Za-z]", en):
                        cache[en] = en
                        continue
                    if not include_pipes and is_skippable(en):
                        skipped += 1
                        continue
                    seen.add(en)
                    pending.append(en)
                    if limit and len(pending) >= limit:
                        return pending, skipped
    return pending, skipped


def apply_cache(translations_dir, cache):
    filled = 0
    for root, _dirs, files in os.walk(translations_dir):
        for name in sorted(files):
            if not name.endswith(".tsv"):
                continue
            path = os.path.join(root, name)
            out_lines = []
            changed = False
            with io.open(path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.rstrip("\r\n")
                    if not line:
                        continue
                    parts = line.split("\t")
                    if len(parts) >= 3 and not parts[2] and parts[1] in cache:
                        zh = cache[parts[1]]
                        if zh:
                            # 仅转义真实控制字符,保留字面量 \r \n(与英文列一致)
                            parts[2] = zh.replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t")
                            changed = True
                            filled += 1
                    out_lines.append("\t".join(parts))
            if changed:
                with io.open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write("\n".join(out_lines) + "\n")
    return filled


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    ap.add_argument("--port", type=int, default=38089)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--target", default="zh-CN")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--only", default="")
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--delay", type=float, default=0.0)
    ap.add_argument("--include-pipes", action="store_true",
                    help="也翻译含 | 的多语言/正则类内部字符串(默认跳过)")
    args = ap.parse_args()

    translations_dir = os.path.join(args.repo, "translations")
    cache_path = os.path.join(args.repo, "reference", "mt-cache.json")
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)

    cache = {}
    if os.path.exists(cache_path):
        try:
            with io.open(cache_path, "r", encoding="utf-8") as f:
                cache = json.load(f)
            print("已加载缓存:%d 条" % len(cache))
        except Exception as e:
            print("缓存损坏,忽略: %s" % e)

    pending, skipped = scan_pending(translations_dir, cache, args.only, args.limit, args.include_pipes)
    print("待翻译唯一原文:%d 条(跳过内部数据 %d 条)" % (len(pending), skipped))
    if not pending:
        save_cache(cache, cache_path)
        print("已回填 %d 条译文到 translations/。" % apply_cache(translations_dir, cache))
        return

    # 分片
    shards = [[] for _ in range(max(1, args.workers))]
    for i, item in enumerate(pending):
        shards[i % len(shards)].append(item)

    lock = threading.Lock()
    out = {}
    stats = {"done": 0, "fail": 0, "total": len(pending), "cache_path": cache_path}

    threads = []
    for shard in shards:
        if not shard:
            continue
        t = threading.Thread(target=worker, args=(shard, out, lock, args.port, args.target,
                                                  args.retries, args.delay, stats))
        t.start()
        threads.append(t)
    for t in threads:
        t.join()

    cache.update(out)
    save_cache(cache, cache_path)
    print("")
    print("机翻完成:成功 %d,失败 %d,缓存共 %d 条" % (stats["done"], stats["fail"], len(cache)))
    print("已回填 %d 条译文到 translations/。" % apply_cache(translations_dir, cache))


if __name__ == "__main__":
    main()
