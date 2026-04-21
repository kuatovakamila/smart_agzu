# Smart AGZU — Mobile Monitoring Application for Automated Gas Stations

> A cross-platform mobile app enabling real-time monitoring for **100+ engineers** — eliminating the need for on-site computer access.

---

## Overview

Smart AGZU is a Flutter-based mobile application built to modernize gas station monitoring. What began as a local server solution evolved into a globally accessible, real-time data platform — empowering field engineers to monitor automated gas stations (AGZU) from anywhere in the world.

---

## Background

The system originally relied on a local-only server with no remote access. To solve this, a full backend and secure distribution layer was architected from the ground up, transforming a closed internal tool into a reliable, globally accessible monitoring platform.

---

## Architecture

### 🐍 Flask API Backend
Built a Python Flask backend to parse and process data from internal station tables — handling data extraction, transformation, and serving it through clean API endpoints.

### 🌐 Cloudflare Tunnel
Integrated Cloudflare Tunnel to securely expose the local backend to the internet — no public IP, no open firewall ports. Enables reliable global data distribution and remote access without compromising security.

### 📱 Flutter Mobile Application
Developed a cross-platform mobile app (iOS & Android) for real-time data visualization, giving engineers instant access to station metrics directly from their phones.

---

## Features

- 📊 **Real-time data visualization** — live monitoring of gas station metrics
- 🌍 **Remote access** — engineers can monitor stations from anywhere globally
- 🔒 **Secure tunnel** — backend exposed safely via Cloudflare, no VPN required
- 📱 **Cross-platform** — single codebase runs on both iOS and Android
- ⚡ **Instant alerts** — engineers stay informed without being on-site

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Mobile | Flutter (Dart) |
| Backend | Python, Flask |
| Tunneling | Cloudflare Tunnel |
| Data Source | Internal station tables |

---

## Impact

- 👷 **100+ engineers** enabled with remote monitoring capabilities
- 🖥️ Eliminated reliance on computer-based, on-site monitoring systems
- 🌐 Transformed a local-only tool into a globally accessible platform
- ⏱️ Enabled real-time decision-making directly from mobile devices
