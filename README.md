# 🪽 Hermes Agent Skills

> A curated collection of custom skills, scripts, and workflows for the [Hermes AI Agent](https://github.com/NousResearch/hermes-agent) by Nous Research.

This repository contains active, class-level skills designed to extend Hermes' capabilities across DevOps, infrastructure management, and local automation, leveraging the agent's autonomous tool-calling and local LLM integration.

### 🔬 AI Lab Playground Setup

**🤖 Node 1: Autonomous Agents**
- **Hardware:** 🖥️ NVIDIA Jetson Orin AGX (64GB)
- **LLM Engine:** 🧠 [Qwen 3.6‑35B‑A3B‑AWQ](https://huggingface.co/QuantTrio/Qwen3.6-35B-A3B-AWQ) (via vLLM)

**🦾 Node 2: Robotics Projects**
- **Hardware:** 🖥️ NVIDIA Jetson Orin Nano Super
- **LLM Engine:** 🧠 [Phi-3-mini-4k-instruct](https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf) (via llama.cpp)

---

## 🛠️ Included Skills

### 🛡️ DevOps & Infrastructure

- **Router Security Audit** (`router-security-audit`)
  Automated routine security audits, log parsing, and scheduled reporting for AsusWRT-Merlin routers.
  * **Features:** SSH-based metric collection, Local LLM log summarization (vLLM/Ollama compatible), and secure Cron-driven reporting workflows via the Hermes gateway.

*(Repository is actively being updated. More skills coming soon.)*

---

## 🚀 Getting Started

To load any of these skills into your Hermes Agent, clone this repository and place the respective skill directory inside your `$HERMES_HOME/skills/` folder.

You can then invoke it during a chat session:

```text
/skill router-security-audit
```
