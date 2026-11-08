#!/usr/bin/env python3
import sys
import argparse
import contextlib
import ipaddress
import socket
import urllib.request
import urllib.parse
import re

# Only http(s) URLs that resolve to a public address may be read. The assistant
# hands this script whatever URL the model asked for, and the model's output is
# untrusted input: `file://` would read local files, and loopback, link-local or
# private addresses would reach services (including cloud metadata endpoints)
# that only this machine can talk to.
ALLOWED_SCHEMES = ("http", "https")

# A page larger than this is not worth the wait, and reading it all is what makes
# a hostile endpoint able to exhaust memory.
MAX_RESPONSE_BYTES = 2 * 1024 * 1024


def _address_of(host):
    """The address `host` names, or None when it is a name the resolver must answer."""
    try:
        address = ipaddress.ip_address(host.split("%", 1)[0])
    except ValueError:
        return None
    if address.version == 6 and address.ipv4_mapped is not None:
        return address.ipv4_mapped
    return address


def _validate_url(url):
    parsed = urllib.parse.urlparse(url)
    scheme = parsed.scheme.lower()
    if scheme not in ALLOWED_SCHEMES:
        raise ValueError(f"refusing {scheme or 'a relative'} URL; only http and https are allowed")
    if not parsed.hostname:
        raise ValueError("the URL names no host")
    # A name is held to the same rule at connect time, by the guard below. Checking a
    # literal here as well is what makes the refusal readable instead of a bare
    # resolver error.
    address = _address_of(parsed.hostname)
    if address is not None and not address.is_global:
        raise ValueError("refusing a URL that names a loopback, private or metadata address")
    return parsed


@contextlib.contextmanager
def _resolve_to_public_addresses():
    """Refuses any name that resolves to a non-public address.

    urllib resolves the name again when it connects, so filtering at that point
    covers redirect hops too: a public host that redirects to localhost fails
    here instead of being followed.
    """
    original = socket.getaddrinfo

    def guarded(host, port, *args, **kwargs):
        resolved = original(host, port, *args, **kwargs)
        allowed = []
        for entry in resolved:
            address = _address_of(entry[4][0])
            if address is not None and address.is_global:
                allowed.append(entry)
        if not allowed:
            raise socket.gaierror(f"{host} does not resolve to a public address")
        return allowed

    socket.getaddrinfo = guarded
    try:
        yield
    finally:
        socket.getaddrinfo = original


def search_web(query, page_num):
    try:
        url = f"https://html.duckduckgo.com/html/?q={urllib.parse.quote(query)}"
        req = urllib.request.Request(
            url,
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'}
        )
        html = urllib.request.urlopen(req, timeout=15).read().decode('utf-8', errors='ignore')

        titles = re.findall(r'<h2 class="result__title">\s*<a[^>]*>(.*?)</a>', html, re.IGNORECASE | re.DOTALL)
        urls = re.findall(r'<a[^>]*class="result__url"[^>]*href="([^"]+)"', html, re.IGNORECASE | re.DOTALL)
        snippets = re.findall(r'<a[^>]*class="result__snippet[^>]*>(.*?)</a>', html, re.IGNORECASE | re.DOTALL)

        results = []

        parsed_urls = []
        for u in urls:
            if u.startswith('//'):
                parsed_urls.append("https:" + u)
            elif 'uddg=' in u:
                try:
                    parsed = urllib.parse.parse_qs(urllib.parse.urlparse(u).query)
                    if 'uddg' in parsed:
                        parsed_urls.append(parsed['uddg'][0])
                    else:
                        parsed_urls.append(u)
                except Exception:
                    parsed_urls.append(u)
            else:
                parsed_urls.append(u)

        def strip_tags(text):
            return re.sub(r'<[^>]+>', '', text).strip()

        start_idx = (page_num - 1) * 5
        end_idx = start_idx + 5

        for i in range(min(len(titles), len(snippets), len(parsed_urls))):
            if i < start_idx:
                continue
            if i >= end_idx:
                break

            title = strip_tags(titles[i])
            snippet = strip_tags(snippets[i])
            u = parsed_urls[i]

            if not u.startswith("http"):
                u = "https://" + u

            if title and u:
                results.append(f"Title: {title}\nURL: {u}\nSnippet: {snippet}")

        if not results:
            return "No useful results found for this page."

        return "\n\n".join(results)
    except Exception as e:
        return f"Error during web search: {str(e)}"


def read_webpage(url):
    try:
        _validate_url(url)

        req = urllib.request.Request(
            url,
            headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'}
        )
        with _resolve_to_public_addresses():
            html = urllib.request.urlopen(req, timeout=15).read(MAX_RESPONSE_BYTES).decode('utf-8', errors='ignore')

        # Remove script and style tags completely
        html = re.sub(r'<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>', '', html, flags=re.IGNORECASE | re.DOTALL)
        html = re.sub(r'<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>', '', html, flags=re.IGNORECASE | re.DOTALL)

        # Remove header, footer, nav
        html = re.sub(r'<nav\b[^<]*(?:(?!<\/nav>)<[^<]*)*<\/nav>', '', html, flags=re.IGNORECASE | re.DOTALL)
        html = re.sub(r'<footer\b[^<]*(?:(?!<\/footer>)<[^<]*)*<\/footer>', '', html, flags=re.IGNORECASE | re.DOTALL)
        html = re.sub(r'<header\b[^<]*(?:(?!<\/header>)<[^<]*)*<\/header>', '', html, flags=re.IGNORECASE | re.DOTALL)
        html = re.sub(r'<aside\b[^<]*(?:(?!<\/aside>)<[^<]*)*<\/aside>', '', html, flags=re.IGNORECASE | re.DOTALL)

        # Extract text from remaining body
        body_match = re.search(r'<body[^>]*>(.*?)</body>', html, re.IGNORECASE | re.DOTALL)
        if body_match:
            body_html = body_match.group(1)
        else:
            body_html = html

        # Strip remaining tags
        text = re.sub(r'<[^>]+>', ' ', body_html)
        # Collapse whitespace
        text = re.sub(r'\s+', ' ', text).strip()

        if len(text) > 10000:
            text = text[:10000] + "\n\n[Content truncated due to length]"

        return text if text else "Could not extract text from this page."
    except Exception as e:
        return f"Error reading webpage: {str(e)}"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["search", "read"], required=True)
    parser.add_argument("--query", type=str, help="Search query")
    parser.add_argument("--page", type=int, default=1, help="Page number (1-indexed)")
    parser.add_argument("--url", type=str, help="URL to read")

    args = parser.parse_args()

    if args.mode == "search":
        if not args.query:
            print("Error: --query is required for search mode")
            sys.exit(1)
        print(search_web(args.query, args.page))
    elif args.mode == "read":
        if not args.url:
            print("Error: --url is required for read mode")
            sys.exit(1)
        print(read_webpage(args.url))
