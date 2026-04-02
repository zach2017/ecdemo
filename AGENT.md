# Building AI Agents with Ollama & Elasticsearch
## A Practical Step-by-Step Guide

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites & Stack Setup](#prerequisites--stack-setup)
3. [Core Agent Framework](#core-agent-framework)
4. [Agent 1 — Smart Email Assistant](#agent-1--smart-email-assistant)
5. [Agent 2 — Automated Ad Posting Agent](#agent-2--automated-ad-posting-agent)
6. [Agent 3 — Web Crawler & Report Builder](#agent-3--web-crawler--report-builder)
7. [Agent 4 — Stock News & Alert Agent](#agent-4--stock-news--alert-agent)
8. [Shared Utilities & Patterns](#shared-utilities--patterns)
9. [Deployment & Monitoring](#deployment--monitoring)

---

## Architecture Overview

Each agent in this guide follows a **Perceive → Reason → Act** loop:

```
External World
     │
     ▼
┌─────────────┐
│  Collectors │  ← crawlers, email readers, APIs, schedulers
└─────────────┘
     │ raw data
     ▼
┌─────────────────────┐
│  Elasticsearch      │  ← index, search, store, deduplicate
│  (Memory/Knowledge) │
└─────────────────────┘
     │ relevant context
     ▼
┌─────────────┐
│  Ollama LLM │  ← reason, summarize, classify, recommend
│  (The Brain)│
└─────────────┘
     │ decisions / text
     ▼
┌─────────────┐
│  Actuators  │  ← send email, post ad, write report, send alert
└─────────────┘
```

### Technology Stack

| Layer | Tool | Role |
|-------|------|------|
| LLM Runtime | Ollama (llama3, mistral, phi3) | Local reasoning, no API cost |
| Vector/Search DB | Elasticsearch 8.x | Memory, search, deduplication |
| Orchestration | Python + APScheduler | Scheduling & task chaining |
| HTTP | httpx / requests | API calls, crawling |
| HTML Parsing | BeautifulSoup4 | Web scraping |
| Email | smtplib / imaplib / yagmail | Send/receive email |
| Reports | Jinja2 + weasyprint | HTML/PDF report generation |
| Config | python-dotenv | Environment management |
| Logging | Python logging + ES | Structured log storage |

---

## Prerequisites & Stack Setup

### Step 1 — Install Ollama

```bash
# macOS / Linux
curl -fsSL https://ollama.com/install.sh | sh

# Pull a capable model (choose based on your RAM)
ollama pull llama3          # 8B params — needs ~8GB RAM
ollama pull mistral         # 7B params — good balance
ollama pull phi3            # 3.8B params — fast on small machines

# Test it
ollama run llama3 "Summarize this in one sentence: Elasticsearch is a distributed search engine."

# Start Ollama API server (runs on http://localhost:11434)
ollama serve
```

### Step 2 — Install & Start Elasticsearch

```bash
# Using Docker (recommended)
docker run -d \
  --name elasticsearch \
  -p 9200:9200 \
  -e "discovery.type=single-node" \
  -e "xpack.security.enabled=false" \
  -e "ES_JAVA_OPTS=-Xms1g -Xmx1g" \
  docker.elastic.co/elasticsearch/elasticsearch:8.13.0

# Verify it's running
curl http://localhost:9200

# Install Python client
pip install elasticsearch==8.13.0
```

### Step 3 — Python Project Setup

```bash
mkdir ai-agents && cd ai-agents
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

pip install \
  elasticsearch \
  httpx \
  beautifulsoup4 \
  yagmail \
  apscheduler \
  jinja2 \
  weasyprint \
  python-dotenv \
  feedparser \
  lxml
```

### Step 4 — Project Structure

```
ai-agents/
├── .env                    # secrets & config
├── core/
│   ├── __init__.py
│   ├── ollama_client.py    # LLM wrapper
│   ├── es_client.py        # Elasticsearch wrapper
│   └── base_agent.py       # base agent class
├── agents/
│   ├── email_agent.py
│   ├── ad_posting_agent.py
│   ├── crawler_agent.py
│   └── stock_agent.py
├── templates/
│   └── report.html         # Jinja2 report template
└── main.py                 # scheduler / entry point
```

### Step 5 — .env File

```ini
# Ollama
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama3

# Elasticsearch
ES_HOST=http://localhost:9200
ES_INDEX_PREFIX=agent_

# Email (Gmail example — use App Password)
EMAIL_USER=you@gmail.com
EMAIL_PASSWORD=your_app_password
IMAP_SERVER=imap.gmail.com
SMTP_SERVER=smtp.gmail.com

# Stock alerts
ALERT_EMAIL=alerts@yourcompany.com
STOCK_TICKERS=AAPL,MSFT,NVDA,TSLA

# Ad posting (Craigslist-style API placeholder)
AD_API_URL=https://api.your-ad-platform.com
AD_API_KEY=your_key_here
```

---

## Core Agent Framework

### core/ollama_client.py

```python
import httpx
import json
import os
from typing import Optional

class OllamaClient:
    def __init__(self):
        self.base_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
        self.model = os.getenv("OLLAMA_MODEL", "llama3")

    def chat(self, messages: list[dict], system: str = None, temperature: float = 0.3) -> str:
        """
        Send a chat request to Ollama.
        messages = [{"role": "user", "content": "..."}, ...]
        """
        payload = {
            "model": self.model,
            "messages": messages,
            "stream": False,
            "options": {"temperature": temperature}
        }
        if system:
            payload["system"] = system

        response = httpx.post(
            f"{self.base_url}/api/chat",
            json=payload,
            timeout=120.0
        )
        response.raise_for_status()
        return response.json()["message"]["content"]

    def embed(self, text: str) -> list[float]:
        """Generate embeddings for semantic search in Elasticsearch."""
        response = httpx.post(
            f"{self.base_url}/api/embeddings",
            json={"model": self.model, "prompt": text},
            timeout=60.0
        )
        response.raise_for_status()
        return response.json()["embedding"]

    def complete(self, prompt: str, system: str = None) -> str:
        """Shortcut for single-turn completions."""
        return self.chat(
            messages=[{"role": "user", "content": prompt}],
            system=system
        )
```

### core/es_client.py

```python
from elasticsearch import Elasticsearch
from datetime import datetime
import hashlib
import os

class ESClient:
    def __init__(self):
        self.es = Elasticsearch(os.getenv("ES_HOST", "http://localhost:9200"))
        self.prefix = os.getenv("ES_INDEX_PREFIX", "agent_")

    def index_name(self, name: str) -> str:
        return f"{self.prefix}{name}"

    def ensure_index(self, name: str, mappings: dict = None):
        """Create index if it doesn't exist."""
        idx = self.index_name(name)
        if not self.es.indices.exists(index=idx):
            body = {"mappings": mappings} if mappings else {}
            self.es.indices.create(index=idx, body=body)
        return idx

    def store(self, index: str, doc: dict, doc_id: str = None) -> str:
        """Store a document. Auto-generate ID if not provided."""
        idx = self.index_name(index)
        doc["indexed_at"] = datetime.utcnow().isoformat()
        result = self.es.index(index=idx, id=doc_id, document=doc)
        return result["_id"]

    def exists(self, index: str, doc_id: str) -> bool:
        """Check if a document already exists (deduplication)."""
        return self.es.exists(index=self.index_name(index), id=doc_id)

    def search(self, index: str, query: dict, size: int = 10) -> list[dict]:
        """Run a search and return hits as plain dicts."""
        result = self.es.search(index=self.index_name(index), query=query, size=size)
        return [hit["_source"] for hit in result["hits"]["hits"]]

    def content_hash(self, text: str) -> str:
        """Create a stable ID from content (for deduplication)."""
        return hashlib.sha256(text.encode()).hexdigest()[:16]

    def store_log(self, agent: str, event: str, detail: str = ""):
        """Store structured agent activity logs."""
        self.store("logs", {
            "agent": agent,
            "event": event,
            "detail": detail,
        })
```

### core/base_agent.py

```python
from core.ollama_client import OllamaClient
from core.es_client import ESClient
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s")

class BaseAgent:
    def __init__(self, name: str):
        self.name = name
        self.llm = OllamaClient()
        self.es = ESClient()
        self.log = logging.getLogger(name)

    def think(self, prompt: str, system: str = None) -> str:
        """Ask the LLM to reason about something."""
        self.log.debug(f"Thinking: {prompt[:80]}...")
        return self.llm.complete(prompt, system=system)

    def remember(self, index: str, doc: dict, doc_id: str = None):
        """Save something to Elasticsearch."""
        return self.es.store(index, doc, doc_id)

    def recall(self, index: str, query: dict, size: int = 10) -> list:
        """Retrieve from Elasticsearch."""
        return self.es.search(index, query, size)

    def log_event(self, event: str, detail: str = ""):
        self.es.store_log(self.name, event, detail)
        self.log.info(f"[{event}] {detail}")

    def run(self):
        raise NotImplementedError("Each agent must implement run()")
```

---

## Agent 1 — Smart Email Assistant

This agent reads your inbox, categorizes emails, drafts replies for important ones, and stores everything in Elasticsearch so you can search your email history semantically.

### What it does

- Connects to Gmail via IMAP
- Reads unread emails
- Uses Ollama to classify each email (urgent / action-required / FYI / spam)
- Drafts suggested replies for urgent emails
- Stores emails + classification in Elasticsearch
- Sends a daily digest email summarizing what needs your attention

### agents/email_agent.py

```python
import imaplib
import email
import yagmail
from email.header import decode_header
from core.base_agent import BaseAgent
import os

class EmailAgent(BaseAgent):
    def __init__(self):
        super().__init__("EmailAgent")
        self.imap_server = os.getenv("IMAP_SERVER", "imap.gmail.com")
        self.email_user = os.getenv("EMAIL_USER")
        self.email_pass = os.getenv("EMAIL_PASSWORD")

        # Ensure Elasticsearch index exists
        self.es.ensure_index("emails", mappings={
            "properties": {
                "from": {"type": "keyword"},
                "subject": {"type": "text"},
                "body": {"type": "text"},
                "category": {"type": "keyword"},
                "priority": {"type": "keyword"},
                "suggested_reply": {"type": "text"},
                "indexed_at": {"type": "date"}
            }
        })

    # ── Step 1: Fetch unread emails ─────────────────────────────────────────

    def fetch_unread(self) -> list[dict]:
        """Connect via IMAP and fetch unread emails."""
        mail = imaplib.IMAP4_SSL(self.imap_server)
        mail.login(self.email_user, self.email_pass)
        mail.select("inbox")

        _, message_ids = mail.search(None, "UNSEEN")
        emails = []

        for mid in message_ids[0].split():
            _, msg_data = mail.fetch(mid, "(RFC822)")
            raw = msg_data[0][1]
            msg = email.message_from_bytes(raw)

            subject, encoding = decode_header(msg["Subject"])[0]
            if isinstance(subject, bytes):
                subject = subject.decode(encoding or "utf-8")

            body = ""
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == "text/plain":
                        body = part.get_payload(decode=True).decode("utf-8", errors="ignore")
                        break
            else:
                body = msg.get_payload(decode=True).decode("utf-8", errors="ignore")

            emails.append({
                "message_id": msg["Message-ID"],
                "from": msg["From"],
                "subject": subject,
                "body": body[:3000],  # Truncate for LLM context
            })

        mail.logout()
        self.log_event("FETCH", f"Found {len(emails)} unread emails")
        return emails

    # ── Step 2: Classify with LLM ───────────────────────────────────────────

    def classify_email(self, subject: str, body: str) -> dict:
        """Ask Ollama to classify and summarize an email."""
        prompt = f"""Analyze this email and respond in this exact format:
CATEGORY: [one of: urgent, action-required, fyi, spam, newsletter]
PRIORITY: [high, medium, low]
SUMMARY: [one sentence summary]
ACTION: [what the recipient needs to do, or 'none']

Email Subject: {subject}
Email Body: {body[:1500]}"""

        response = self.think(prompt, system=(
            "You are an email assistant. Be concise and accurate. "
            "Only output the structured format, no extra text."
        ))

        # Parse structured response
        result = {"category": "fyi", "priority": "low", "summary": "", "action": "none"}
        for line in response.strip().split("\n"):
            if line.startswith("CATEGORY:"):
                result["category"] = line.split(":", 1)[1].strip().lower()
            elif line.startswith("PRIORITY:"):
                result["priority"] = line.split(":", 1)[1].strip().lower()
            elif line.startswith("SUMMARY:"):
                result["summary"] = line.split(":", 1)[1].strip()
            elif line.startswith("ACTION:"):
                result["action"] = line.split(":", 1)[1].strip()
        return result

    # ── Step 3: Draft reply for urgent emails ───────────────────────────────

    def draft_reply(self, sender: str, subject: str, body: str, action: str) -> str:
        """Use Ollama to draft a professional reply."""
        prompt = f"""Draft a professional email reply.
Sender: {sender}
Subject: {subject}
Required action: {action}
Original message: {body[:1000]}

Write a concise, professional reply. Sign off as 'The Team'."""

        return self.think(prompt, system=(
            "You are a professional email writer. Be polite, clear, and brief."
        ))

    # ── Step 4: Store in Elasticsearch ──────────────────────────────────────

    def store_email(self, email_data: dict, classification: dict, reply: str = ""):
        """Store processed email in Elasticsearch."""
        doc_id = self.es.content_hash(email_data.get("message_id", email_data["subject"]))
        if self.es.exists("emails", doc_id):
            return  # Already processed

        self.remember("emails", {
            **email_data,
            **classification,
            "suggested_reply": reply,
        }, doc_id=doc_id)

    # ── Step 5: Send daily digest ────────────────────────────────────────────

    def send_digest(self, processed: list[dict]):
        """Send a summary email of what needs attention."""
        urgent = [e for e in processed if e["classification"]["priority"] == "high"]

        if not urgent:
            self.log_event("DIGEST", "No urgent items — skipping digest")
            return

        body_lines = ["Here are the emails that need your attention today:\n"]
        for item in urgent:
            body_lines.append(f"📧 From: {item['email']['from']}")
            body_lines.append(f"   Subject: {item['email']['subject']}")
            body_lines.append(f"   Summary: {item['classification']['summary']}")
            body_lines.append(f"   Action: {item['classification']['action']}")
            if item.get("reply"):
                body_lines.append(f"   Suggested reply:\n{item['reply']}\n")
            body_lines.append("---")

        yg = yagmail.SMTP(self.email_user, self.email_pass)
        yg.send(
            to=self.email_user,
            subject=f"📬 Daily Email Digest — {len(urgent)} items need attention",
            contents="\n".join(body_lines)
        )
        self.log_event("DIGEST_SENT", f"{len(urgent)} urgent items")

    # ── Main run loop ────────────────────────────────────────────────────────

    def run(self):
        self.log.info("EmailAgent starting...")
        emails = self.fetch_unread()
        processed = []

        for e in emails:
            classification = self.classify_email(e["subject"], e["body"])
            reply = ""
            if classification["priority"] == "high":
                reply = self.draft_reply(
                    e["from"], e["subject"], e["body"], classification["action"]
                )
            self.store_email(e, classification, reply)
            processed.append({"email": e, "classification": classification, "reply": reply})
            self.log.info(f"  [{classification['priority'].upper()}] {e['subject'][:60]}")

        self.send_digest(processed)
        self.log.info(f"EmailAgent done. Processed {len(emails)} emails.")
```

### Searching your email history

```python
# Find all emails about invoices using Elasticsearch full-text search
results = agent.recall("emails", {
    "match": {"body": "invoice payment due"}
}, size=5)

for r in results:
    print(r["subject"], "-", r["summary"])
```

---

## Agent 2 — Automated Ad Posting Agent

This agent manages classified ad campaigns. It generates ad copy with Ollama, posts ads to platforms, tracks which ads were posted (to avoid duplicates), and monitors response rates.

### What it does

- Takes a product/service description as input
- Uses Ollama to generate compelling ad copy variants
- Posts ads to platforms via their API
- Tracks all posted ads in Elasticsearch
- Detects and skips duplicate/expired ads
- Reports on ad performance

### agents/ad_posting_agent.py

```python
import httpx
from datetime import datetime, timedelta
from core.base_agent import BaseAgent
import os

class AdPostingAgent(BaseAgent):
    def __init__(self):
        super().__init__("AdPostingAgent")
        self.ad_api_url = os.getenv("AD_API_URL")
        self.ad_api_key = os.getenv("AD_API_KEY")

        self.es.ensure_index("ads", mappings={
            "properties": {
                "title": {"type": "text"},
                "body": {"type": "text"},
                "category": {"type": "keyword"},
                "platform": {"type": "keyword"},
                "status": {"type": "keyword"},
                "posted_at": {"type": "date"},
                "expires_at": {"type": "date"},
                "ad_id": {"type": "keyword"},
                "indexed_at": {"type": "date"}
            }
        })

    # ── Step 1: Generate ad copy with Ollama ─────────────────────────────────

    def generate_ad(self, product: dict) -> dict:
        """
        product = {
          "name": "Used MacBook Pro 2021",
          "description": "M1 chip, 16GB RAM, 512GB SSD, excellent condition",
          "price": 900,
          "category": "electronics",
          "location": "Austin, TX"
        }
        """
        prompt = f"""Write a compelling classified ad for this item.

Product: {product['name']}
Details: {product['description']}
Price: ${product['price']}
Location: {product['location']}
Category: {product['category']}

Respond in this format:
TITLE: [attention-grabbing title, max 80 chars]
BODY: [persuasive body text, 3-4 sentences, highlight value and condition]
TAGS: [5 relevant search tags, comma separated]"""

        response = self.think(prompt, system=(
            "You are an expert copywriter for classified ads. "
            "Write compelling, honest ads that attract serious buyers."
        ))

        result = {"title": "", "body": "", "tags": []}
        for line in response.strip().split("\n"):
            if line.startswith("TITLE:"):
                result["title"] = line.split(":", 1)[1].strip()
            elif line.startswith("BODY:"):
                result["body"] = line.split(":", 1)[1].strip()
            elif line.startswith("TAGS:"):
                result["tags"] = [t.strip() for t in line.split(":", 1)[1].split(",")]
        return result

    # ── Step 2: Check for duplicate / active ads ──────────────────────────────

    def is_already_posted(self, product_name: str, platform: str) -> bool:
        """Check Elasticsearch if a similar active ad exists."""
        results = self.recall("ads", {
            "bool": {
                "must": [
                    {"match": {"title": product_name}},
                    {"term": {"platform": platform}},
                    {"term": {"status": "active"}},
                ]
            }
        }, size=1)
        return len(results) > 0

    # ── Step 3: Post to ad platform ───────────────────────────────────────────

    def post_ad(self, ad_copy: dict, product: dict, platform: str = "craigslist") -> dict:
        """POST the ad to the platform API. Returns platform response."""
        payload = {
            "title": ad_copy["title"],
            "body": ad_copy["body"],
            "category": product["category"],
            "price": product["price"],
            "location": product["location"],
            "tags": ad_copy["tags"],
        }
        headers = {"Authorization": f"Bearer {self.ad_api_key}"}

        # NOTE: Replace with your actual platform's API endpoint
        response = httpx.post(
            f"{self.ad_api_url}/ads",
            json=payload,
            headers=headers,
            timeout=30.0
        )
        response.raise_for_status()
        return response.json()

    # ── Step 4: Store ad record ───────────────────────────────────────────────

    def store_ad(self, product: dict, ad_copy: dict, platform: str, platform_response: dict):
        doc_id = self.es.content_hash(f"{product['name']}-{platform}")
        expires = (datetime.utcnow() + timedelta(days=30)).isoformat()
        self.remember("ads", {
            "product_name": product["name"],
            "title": ad_copy["title"],
            "body": ad_copy["body"],
            "tags": ad_copy["tags"],
            "category": product["category"],
            "platform": platform,
            "status": "active",
            "price": product["price"],
            "location": product["location"],
            "posted_at": datetime.utcnow().isoformat(),
            "expires_at": expires,
            "ad_id": platform_response.get("id", "unknown"),
        }, doc_id=doc_id)

    # ── Step 5: Performance report ────────────────────────────────────────────

    def performance_report(self) -> str:
        """Ask Ollama to summarize our ad performance from ES data."""
        active_ads = self.recall("ads", {"term": {"status": "active"}}, size=50)
        if not active_ads:
            return "No active ads found."

        ad_summary = "\n".join([
            f"- {a['title']} | {a['platform']} | Posted: {a['posted_at'][:10]}"
            for a in active_ads
        ])
        prompt = f"""Summarize this ad campaign data and give 3 recommendations:

Active Ads ({len(active_ads)} total):
{ad_summary}

Provide: overall status, top performing categories, and 3 concrete improvement tips."""

        return self.think(prompt)

    # ── Main run loop ─────────────────────────────────────────────────────────

    def run(self, products: list[dict], platforms: list[str] = None):
        platforms = platforms or ["craigslist", "facebook_marketplace"]
        self.log.info(f"AdPostingAgent starting with {len(products)} products")

        for product in products:
            for platform in platforms:
                if self.is_already_posted(product["name"], platform):
                    self.log.info(f"Skipping {product['name']} on {platform} — already active")
                    continue

                ad_copy = self.generate_ad(product)
                self.log.info(f"Generated: '{ad_copy['title']}'")

                try:
                    api_response = self.post_ad(ad_copy, product, platform)
                    self.store_ad(product, ad_copy, platform, api_response)
                    self.log_event("AD_POSTED", f"{product['name']} on {platform}")
                except Exception as e:
                    self.log_event("AD_FAILED", str(e))

        print(self.performance_report())
```

---

## Agent 3 — Web Crawler & Report Builder

This agent crawls one or more websites on a schedule, extracts and indexes content in Elasticsearch, detects changes, and produces a structured HTML/PDF report summarized by Ollama.

### What it does

- Crawls a list of seed URLs recursively
- Extracts clean text from HTML pages
- Deduplicates via content hashing in Elasticsearch
- Detects changed pages since last crawl
- Uses Ollama to write an executive summary of each site
- Generates a formatted HTML report with charts

### agents/crawler_agent.py

```python
import httpx
from bs4 import BeautifulSoup
from urllib.parse import urljoin, urlparse
from datetime import datetime
from jinja2 import Template
from core.base_agent import BaseAgent

REPORT_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
  <title>Web Crawl Report — {{ date }}</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 900px; margin: 40px auto; color: #333; }
    h1 { color: #1a73e8; border-bottom: 2px solid #1a73e8; padding-bottom: 8px; }
    h2 { color: #444; margin-top: 30px; }
    .site-card { border: 1px solid #ddd; border-radius: 8px; padding: 20px; margin: 20px 0; }
    .summary { background: #f0f7ff; padding: 15px; border-radius: 6px; font-style: italic; }
    .stat { display: inline-block; background: #e8f5e9; padding: 6px 14px; border-radius: 20px;
            margin: 4px; font-size: 13px; font-weight: bold; }
    .new { background: #fff3e0; }
    .changed { background: #fce4ec; }
    table { width: 100%; border-collapse: collapse; margin-top: 10px; }
    th { background: #1a73e8; color: white; padding: 8px; }
    td { padding: 8px; border-bottom: 1px solid #eee; }
    tr:hover { background: #f5f5f5; }
  </style>
</head>
<body>
  <h1>🕷️ Web Crawl Report</h1>
  <p>Generated: {{ date }} | Total sites crawled: {{ sites|length }}</p>

  {% for site in sites %}
  <div class="site-card">
    <h2>{{ site.domain }}</h2>
    <span class="stat">📄 {{ site.pages_crawled }} pages</span>
    <span class="stat new">🆕 {{ site.new_pages }} new</span>
    <span class="stat changed">✏️ {{ site.changed_pages }} changed</span>

    <div class="summary">
      <strong>AI Summary:</strong><br>{{ site.summary }}
    </div>

    <h3>Pages Found</h3>
    <table>
      <tr><th>URL</th><th>Title</th><th>Status</th><th>Words</th></tr>
      {% for page in site.pages[:20] %}
      <tr>
        <td><a href="{{ page.url }}" target="_blank">{{ page.url[-60:] }}</a></td>
        <td>{{ page.title[:50] }}</td>
        <td>{{ page.status }}</td>
        <td>{{ page.word_count }}</td>
      </tr>
      {% endfor %}
    </table>
  </div>
  {% endfor %}
</body>
</html>
"""

class CrawlerAgent(BaseAgent):
    def __init__(self):
        super().__init__("CrawlerAgent")
        self.es.ensure_index("pages", mappings={
            "properties": {
                "url": {"type": "keyword"},
                "domain": {"type": "keyword"},
                "title": {"type": "text"},
                "content": {"type": "text"},
                "content_hash": {"type": "keyword"},
                "word_count": {"type": "integer"},
                "crawled_at": {"type": "date"},
                "status": {"type": "keyword"},
                "indexed_at": {"type": "date"}
            }
        })

    # ── Step 1: Fetch and parse a single page ─────────────────────────────────

    def fetch_page(self, url: str) -> dict | None:
        """Download a page and extract clean text."""
        try:
            response = httpx.get(url, timeout=15.0, follow_redirects=True,
                                 headers={"User-Agent": "Mozilla/5.0 AgentBot/1.0"})
            response.raise_for_status()
        except Exception as e:
            self.log.warning(f"Failed to fetch {url}: {e}")
            return None

        soup = BeautifulSoup(response.text, "lxml")
        for tag in soup(["script", "style", "nav", "footer", "header"]):
            tag.decompose()

        title = soup.title.string.strip() if soup.title else url
        content = " ".join(soup.get_text(separator=" ").split())

        return {
            "url": url,
            "domain": urlparse(url).netloc,
            "title": title,
            "content": content[:10000],
            "word_count": len(content.split()),
            "content_hash": self.es.content_hash(content[:2000]),
        }

    # ── Step 2: Discover links on a page ─────────────────────────────────────

    def extract_links(self, html: str, base_url: str, same_domain_only: bool = True) -> list[str]:
        soup = BeautifulSoup(html, "lxml")
        base_domain = urlparse(base_url).netloc
        links = set()
        for a in soup.find_all("a", href=True):
            full_url = urljoin(base_url, a["href"])
            parsed = urlparse(full_url)
            if parsed.scheme in ("http", "https"):
                if not same_domain_only or parsed.netloc == base_domain:
                    links.add(full_url.split("#")[0])  # strip anchors
        return list(links)

    # ── Step 3: Crawl a site with depth limit ─────────────────────────────────

    def crawl_site(self, seed_url: str, max_pages: int = 30) -> list[dict]:
        """Breadth-first crawl from seed URL."""
        domain = urlparse(seed_url).netloc
        visited = set()
        queue = [seed_url]
        pages = []

        self.log.info(f"Crawling {domain} (max {max_pages} pages)...")

        while queue and len(pages) < max_pages:
            url = queue.pop(0)
            if url in visited:
                continue
            visited.add(url)

            page = self.fetch_page(url)
            if not page:
                continue

            # Determine if this is new or changed in ES
            doc_id = self.es.content_hash(url)
            existing = self.es.search("pages", {"term": {"url": url}}, size=1)

            if existing:
                prev_hash = existing[0].get("content_hash", "")
                page["status"] = "changed" if page["content_hash"] != prev_hash else "unchanged"
            else:
                page["status"] = "new"

            page["crawled_at"] = datetime.utcnow().isoformat()
            self.remember("pages", page, doc_id=doc_id)
            pages.append(page)
            self.log.info(f"  [{page['status'].upper()}] {url[:70]}")

            # Add discovered links to queue
            raw_html = httpx.get(url, timeout=10.0).text
            for link in self.extract_links(raw_html, url):
                if link not in visited:
                    queue.append(link)

        return pages

    # ── Step 4: AI summary of the site ───────────────────────────────────────

    def summarize_site(self, domain: str, pages: list[dict]) -> str:
        """Ask Ollama to summarize what this site is about."""
        content_snippets = "\n\n".join([
            f"Page: {p['title']}\n{p['content'][:500]}"
            for p in pages[:8]
        ])

        prompt = f"""Based on these pages from {domain}, write a 3-4 sentence executive summary:
- What does this website do / offer?
- Who is the target audience?
- What are the key topics or services?
- Any notable changes or new content?

Pages sampled:
{content_snippets}"""

        return self.think(prompt, system=(
            "You are a web analyst. Write clear, concise summaries for business stakeholders."
        ))

    # ── Step 5: Generate HTML report ─────────────────────────────────────────

    def generate_report(self, sites_data: list[dict]) -> str:
        template = Template(REPORT_TEMPLATE)
        html = template.render(
            date=datetime.now().strftime("%Y-%m-%d %H:%M"),
            sites=sites_data
        )
        report_path = f"report_{datetime.now().strftime('%Y%m%d_%H%M')}.html"
        with open(report_path, "w") as f:
            f.write(html)
        self.log.info(f"Report saved: {report_path}")
        return report_path

    # ── Main run loop ─────────────────────────────────────────────────────────

    def run(self, urls: list[str], max_pages_per_site: int = 30):
        self.log.info(f"CrawlerAgent starting on {len(urls)} sites")
        sites_data = []

        for url in urls:
            domain = urlparse(url).netloc
            pages = self.crawl_site(url, max_pages=max_pages_per_site)
            summary = self.summarize_site(domain, pages)

            sites_data.append({
                "domain": domain,
                "pages_crawled": len(pages),
                "new_pages": sum(1 for p in pages if p["status"] == "new"),
                "changed_pages": sum(1 for p in pages if p["status"] == "changed"),
                "summary": summary,
                "pages": pages,
            })

        report_path = self.generate_report(sites_data)
        self.log_event("REPORT_GENERATED", report_path)
        return report_path
```

---

## Agent 4 — Stock News & Alert Agent

This agent watches financial news sites, uses Ollama to analyze sentiment and extract stock signals, tracks positions in Elasticsearch, and emails you alerts when meaningful signals are detected.

### What it does

- Reads RSS feeds from financial news sites (Reuters, Yahoo Finance, Seeking Alpha, etc.)
- Extracts mentions of your tracked tickers
- Uses Ollama to score sentiment (bullish / bearish / neutral) and confidence
- Stores signals in Elasticsearch for trend analysis
- Sends email alerts when multiple signals align

### agents/stock_agent.py

```python
import feedparser
import yagmail
from datetime import datetime, timedelta
from collections import defaultdict
from core.base_agent import BaseAgent
import os

NEWS_FEEDS = [
    "https://feeds.finance.yahoo.com/rss/2.0/headline",
    "https://www.reutersagency.com/feed/?best-topics=business-finance&post_type=best",
    "https://feeds.marketwatch.com/marketwatch/topstories/",
    "https://seekingalpha.com/feed.xml",
]

class StockAgent(BaseAgent):
    def __init__(self):
        super().__init__("StockAgent")
        self.tickers = [t.strip() for t in os.getenv("STOCK_TICKERS", "AAPL,MSFT").split(",")]
        self.alert_email = os.getenv("ALERT_EMAIL")
        self.email_user = os.getenv("EMAIL_USER")
        self.email_pass = os.getenv("EMAIL_PASSWORD")

        self.es.ensure_index("stock_signals", mappings={
            "properties": {
                "ticker": {"type": "keyword"},
                "headline": {"type": "text"},
                "source": {"type": "keyword"},
                "sentiment": {"type": "keyword"},
                "confidence": {"type": "float"},
                "reasoning": {"type": "text"},
                "recommendation": {"type": "keyword"},
                "article_url": {"type": "keyword"},
                "published": {"type": "date"},
                "indexed_at": {"type": "date"}
            }
        })

    # ── Step 1: Fetch news articles from RSS feeds ────────────────────────────

    def fetch_news(self) -> list[dict]:
        """Parse RSS feeds and return articles mentioning tracked tickers."""
        articles = []
        for feed_url in NEWS_FEEDS:
            try:
                feed = feedparser.parse(feed_url)
                for entry in feed.entries[:30]:
                    title = entry.get("title", "")
                    summary = entry.get("summary", "")
                    text = f"{title} {summary}"

                    # Check if any tracked ticker is mentioned
                    mentioned = [t for t in self.tickers if t in text.upper()]
                    if mentioned:
                        articles.append({
                            "headline": title,
                            "summary": summary[:1000],
                            "url": entry.get("link", ""),
                            "source": feed.feed.get("title", feed_url),
                            "published": entry.get("published", datetime.utcnow().isoformat()),
                            "tickers_mentioned": mentioned,
                        })
            except Exception as e:
                self.log.warning(f"Feed error {feed_url}: {e}")

        self.log_event("NEWS_FETCH", f"{len(articles)} relevant articles found")
        return articles

    # ── Step 2: Analyze sentiment with Ollama ─────────────────────────────────

    def analyze_article(self, article: dict) -> dict:
        """Use Ollama to score each article's market signal."""
        tickers_str = ", ".join(article["tickers_mentioned"])
        prompt = f"""Analyze this financial news article for stock market signals.
Tickers mentioned: {tickers_str}
Headline: {article['headline']}
Content: {article['summary']}

Respond ONLY in this format (no other text):
SENTIMENT: [bullish/bearish/neutral]
CONFIDENCE: [0.0-1.0]
RECOMMENDATION: [buy/sell/hold/watch]
REASONING: [one clear sentence explaining your assessment]"""

        response = self.think(prompt, system=(
            "You are a senior financial analyst. Be precise and conservative in your assessments. "
            "Base judgments purely on the news content, not general market opinion."
        ))

        result = {
            "sentiment": "neutral", "confidence": 0.5,
            "recommendation": "watch", "reasoning": ""
        }
        for line in response.strip().split("\n"):
            if line.startswith("SENTIMENT:"):
                result["sentiment"] = line.split(":", 1)[1].strip().lower()
            elif line.startswith("CONFIDENCE:"):
                try:
                    result["confidence"] = float(line.split(":", 1)[1].strip())
                except ValueError:
                    pass
            elif line.startswith("RECOMMENDATION:"):
                result["recommendation"] = line.split(":", 1)[1].strip().lower()
            elif line.startswith("REASONING:"):
                result["reasoning"] = line.split(":", 1)[1].strip()
        return result

    # ── Step 3: Store signals in Elasticsearch ────────────────────────────────

    def store_signal(self, article: dict, analysis: dict, ticker: str):
        """Store one signal per ticker mentioned per article."""
        doc_id = self.es.content_hash(f"{ticker}-{article['url']}")
        if self.es.exists("stock_signals", doc_id):
            return  # Already analyzed this article

        self.remember("stock_signals", {
            "ticker": ticker,
            "headline": article["headline"],
            "source": article["source"],
            "article_url": article["url"],
            "published": article["published"],
            **analysis,
        }, doc_id=doc_id)

    # ── Step 4: Aggregate signals & detect alerts ─────────────────────────────

    def check_for_alerts(self) -> list[dict]:
        """
        Look at signals from the last 24h.
        Alert if 3+ bullish or 3+ bearish signals for the same ticker.
        """
        since = (datetime.utcnow() - timedelta(hours=24)).isoformat()
        signals = self.recall("stock_signals", {
            "bool": {
                "must": [{"range": {"indexed_at": {"gte": since}}}],
                "must_not": [{"term": {"sentiment": "neutral"}}]
            }
        }, size=200)

        # Aggregate by ticker
        by_ticker = defaultdict(lambda: {"bullish": [], "bearish": []})
        for s in signals:
            by_ticker[s["ticker"]][s["sentiment"]].append(s)

        alerts = []
        for ticker, data in by_ticker.items():
            if len(data["bullish"]) >= 3:
                alerts.append({"ticker": ticker, "direction": "BULLISH", "signals": data["bullish"]})
            if len(data["bearish"]) >= 3:
                alerts.append({"ticker": ticker, "direction": "BEARISH", "signals": data["bearish"]})

        return alerts

    # ── Step 5: Generate alert email ──────────────────────────────────────────

    def send_alerts(self, alerts: list[dict]):
        if not alerts:
            self.log.info("No alerts to send.")
            return

        for alert in alerts:
            # Ask Ollama for a final recommendation synthesis
            signals_text = "\n".join([
                f"- {s['headline']} (confidence: {s['confidence']:.1f})"
                for s in alert["signals"]
            ])

            synthesis = self.think(
                f"Based on these {alert['direction']} signals for {alert['ticker']}, "
                f"write a 2-sentence investment alert for a retail investor:\n{signals_text}",
                system="You are a cautious financial advisor. Always note that this is not financial advice."
            )

            emoji = "📈" if alert["direction"] == "BULLISH" else "📉"
            subject = f"{emoji} Stock Alert: {alert['ticker']} — {alert['direction']} Signal"

            body = f"""Stock Alert for {alert['ticker']}

Signal: {alert['direction']}
Sources: {len(alert['signals'])} articles in the last 24 hours

AI Analysis:
{synthesis}

Articles:
""" + "\n".join([f"• {s['headline']}\n  {s['article_url']}" for s in alert["signals"]])

            yg = yagmail.SMTP(self.email_user, self.email_pass)
            yg.send(to=self.alert_email, subject=subject, contents=body)
            self.log_event("ALERT_SENT", f"{ticker} {alert['direction']}")

    # ── Step 6: Portfolio summary report ──────────────────────────────────────

    def portfolio_summary(self) -> str:
        """Generate a weekly summary of all signals for tracked tickers."""
        since = (datetime.utcnow() - timedelta(days=7)).isoformat()
        summaries = []

        for ticker in self.tickers:
            signals = self.recall("stock_signals", {
                "bool": {
                    "must": [
                        {"term": {"ticker": ticker}},
                        {"range": {"indexed_at": {"gte": since}}}
                    ]
                }
            }, size=50)

            if not signals:
                summaries.append(f"{ticker}: No news this week.")
                continue

            bullish = sum(1 for s in signals if s["sentiment"] == "bullish")
            bearish = sum(1 for s in signals if s["sentiment"] == "bearish")
            avg_confidence = sum(s["confidence"] for s in signals) / len(signals)

            summaries.append(
                f"{ticker}: {len(signals)} articles — "
                f"📈 {bullish} bullish / 📉 {bearish} bearish "
                f"(avg confidence: {avg_confidence:.2f})"
            )

        report_data = "\n".join(summaries)
        return self.think(
            f"Write a weekly portfolio newsletter based on this news signal data:\n{report_data}",
            system="You are a financial newsletter writer. Be informative, balanced, and always remind "
                   "readers that this is not financial advice."
        )

    # ── Main run loop ─────────────────────────────────────────────────────────

    def run(self):
        self.log.info(f"StockAgent watching: {', '.join(self.tickers)}")
        articles = self.fetch_news()

        for article in articles:
            analysis = self.analyze_article(article)
            for ticker in article["tickers_mentioned"]:
                self.store_signal(article, analysis, ticker)
            self.log.info(
                f"  {article['headline'][:60]} → "
                f"{analysis['sentiment']} ({analysis['confidence']:.2f})"
            )

        alerts = self.check_for_alerts()
        self.send_alerts(alerts)
        self.log.info(f"StockAgent done. {len(articles)} articles, {len(alerts)} alerts.")
```

---

## Shared Utilities & Patterns

### main.py — Scheduling All Agents

```python
from apscheduler.schedulers.blocking import BlockingScheduler
from dotenv import load_dotenv
from agents.email_agent import EmailAgent
from agents.ad_posting_agent import AdPostingAgent
from agents.crawler_agent import CrawlerAgent
from agents.stock_agent import StockAgent

load_dotenv()

scheduler = BlockingScheduler()

# Email: check every 30 minutes
@scheduler.scheduled_job("interval", minutes=30, id="email")
def run_email():
    EmailAgent().run()

# Stock news: every 2 hours during market hours
@scheduler.scheduled_job("cron", hour="9-16", minute="0", id="stocks")
def run_stocks():
    StockAgent().run()

# Crawler: every day at 6 AM
@scheduler.scheduled_job("cron", hour=6, id="crawler")
def run_crawler():
    CrawlerAgent().run(urls=[
        "https://techcrunch.com",
        "https://news.ycombinator.com",
        "https://www.producthunt.com",
    ])

# Ad posting: check for new products to post at 8 AM
@scheduler.scheduled_job("cron", hour=8, id="ads")
def run_ads():
    products = [
        {
            "name": "Used MacBook Pro 2021",
            "description": "M1 chip, 16GB RAM, excellent condition, charger included",
            "price": 900,
            "category": "electronics",
            "location": "Austin, TX"
        }
    ]
    AdPostingAgent().run(products=products)

if __name__ == "__main__":
    print("🤖 All agents scheduled. Starting scheduler...")
    scheduler.start()
```

### Elasticsearch Queries — Useful Patterns

```python
# Full-text search across all crawled pages
results = es.search("pages", {
    "multi_match": {
        "query": "machine learning breakthrough",
        "fields": ["title^2", "content"]
    }
})

# Find all bearish signals for NVDA this week
results = es.search("stock_signals", {
    "bool": {
        "must": [
            {"term": {"ticker": "NVDA"}},
            {"term": {"sentiment": "bearish"}},
            {"range": {"indexed_at": {"gte": "now-7d"}}}
        ]
    }
})

# Aggregation: count emails by category
es_client.es.search(
    index="agent_emails",
    aggs={"by_category": {"terms": {"field": "category"}}}
)
```

---

## Deployment & Monitoring

### Running Locally

```bash
# Start Elasticsearch
docker start elasticsearch

# Start Ollama
ollama serve &

# Run all agents
source venv/bin/activate
python main.py
```

### Docker Compose (Production Setup)

```yaml
version: "3.8"
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.13.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - ES_JAVA_OPTS=-Xms1g -Xmx1g
    ports:
      - "9200:9200"
    volumes:
      - esdata:/usr/share/elasticsearch/data

  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_models:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]  # Remove if no GPU

  agents:
    build: .
    depends_on:
      - elasticsearch
      - ollama
    env_file: .env
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - ES_HOST=http://elasticsearch:9200

volumes:
  esdata:
  ollama_models:
```

### Monitoring Agent Health

```python
# Add to base_agent.py — query agent activity logs
def health_report(self) -> dict:
    since = (datetime.utcnow() - timedelta(hours=24)).isoformat()
    events = self.recall("logs", {
        "bool": {
            "must": [
                {"term": {"agent": self.name}},
                {"range": {"indexed_at": {"gte": since}}}
            ]
        }
    }, size=100)
    return {
        "agent": self.name,
        "events_last_24h": len(events),
        "last_event": events[-1] if events else None,
    }
```

### Tips & Best Practices

**Ollama Model Selection**
- Use `llama3` or `mistral` for complex reasoning (email triage, stock analysis)
- Use `phi3` for high-volume, simple tasks (classification, tagging) — it's 3× faster
- Set `temperature=0.1` for structured output tasks; `0.7` for creative copy

**Elasticsearch Indexing**
- Always create explicit mappings before storing — prevents auto-mapping surprises
- Use `keyword` type for fields you'll filter/aggregate on; `text` for full-text search
- Content-hash your documents for idempotent, duplicate-free indexing

**Rate Limiting & Politeness**
- Add `time.sleep(1)` between requests in the crawler
- Respect `robots.txt` in production
- Cache Ollama responses for identical inputs using ES as the cache layer

**Scaling Up**
- Replace APScheduler with Celery + Redis for distributed, fault-tolerant task execution
- Add Kibana (`docker run -p 5601:5601 kibana:8.13.0`) for visual dashboards over your ES data
- Use Ollama's `/api/embeddings` endpoint + ES `dense_vector` field for semantic search

---

*This guide uses only open-source, locally-run components — no OpenAI API costs, no data sent to third parties. All reasoning happens on your machine via Ollama.*