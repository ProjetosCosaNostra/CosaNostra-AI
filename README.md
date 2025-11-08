# 🎬 CosaNostra AI  

![Python](https://img.shields.io/badge/Python-3.10-blue?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115-green?logo=fastapi&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-ready-blue?logo=docker&logoColor=white)
![Render](https://img.shields.io/badge/Deployed%20on-Render-orange?logo=render&logoColor=white)
![License](https://img.shields.io/badge/License-Private-red)
![Status](https://img.shields.io/badge/Build-Passing-success)

> **“O código da família nunca falha.”**  
> O estúdio inteligente que dá voz, rosto e emoção às histórias.  
> Crie, narre e produza conteúdos lendários com Inteligência Artificial.

---

## 🧠 Sobre o Projeto  

**CosaNostra AI** é um ecossistema completo de IA multimodal — unindo **voz, vídeo e imagem** em um backend orquestrado por **FastAPI + Docker**.  

🔹 **Voz** – TTS (Text-to-Speech) com geração natural de fala.  
🔹 **Vídeo** – Text2Video, Lip Sync e geração criativa.  
🔹 **Imagens** – Criação e edição com IA.  
🔹 **Assets** – Biblioteca de templates e produções automatizadas.  

---

## ⚙️ Estrutura do Projeto  

```bash
E:\CosaNostra-AI
├── backend/                # Backend principal (FastAPI)
│   ├── main.py             # Core da aplicação e endpoints
│   ├── static/             # Recursos estáticos (logos, trailers)
│   └── scripts/            # Scripts auxiliares (geração de trailers, etc.)
├── Dockerfile.backend      # Imagem Docker do backend
├── Dockerfile.tts          # Imagem Docker do serviço TTS
├── docker-compose.yml      # Orquestra containers (backend, TTS, DB, Redis)
└── .gitignore              # Exclusões para build limpo
🚀 Executar Localmente

Pré-requisitos:
Python 3.10+ • Docker Desktop • Git

# Clone o repositório
git clone https://github.com/ProjetosCosaNostra/CosaNostra-AI.git
cd CosaNostra-AI

# Inicie o ambiente local
Set-ExecutionPolicy Bypass -Scope Process -Force
.\init_project.ps1


Após inicializar:

Backend: http://localhost:8000/docs  
TTS:     http://localhost:8002/docs  

🧩 Principais Endpoints
Método	Rota	Descrição
GET	/health	Testa o status do backend
POST	/api/tts	Gera fala (Text → Voz)
GET	/media/{filename}	Retorna arquivos gerados
GET	/api/trailer?lang=pt	Reproduz o trailer em português
GET	/api/trailer?lang=en	Reproduz o trailer em inglês
GET	/api/trailer?lang=it	Reproduz o trailer em italiano
🧱 Stack Técnica

Python 3.10

FastAPI + Uvicorn

Docker Compose

PostgreSQL + Redis

Coqui-TTS (Text-to-Speech)

HTML5 + JS (Frontend integrado)

🌐 Deploy

🔧 Deploy gratuito via Render.com

# Build das imagens
docker-compose build

# Executar ambiente
docker-compose up


Após o deploy, acesse:

https://cosanostra-ai-backend.onrender.com

🎧 Geração Automática de Trailers
cd backend/scripts
python generate_trailer_audio.py


Arquivos gerados:

backend/static/trailer_cosanostra_pt.mp3
backend/static/trailer_cosanostra_en.mp3
backend/static/trailer_cosanostra_it.mp3

🏗️ Estrutura Modular

Cada serviço do CosaNostra AI é independente e pode ser escalado individualmente:

Backend → coordena as requisições e rotas REST.

TTS Service → gera fala a partir de texto.

Database → armazena históricos e media.

Redis → gerencia cache e tarefas assíncronas.

🕵️‍♂️ Créditos e Licença

Este projeto foi desenvolvido por CosaNostra AI Studio
® Marca registrada — todos os direitos reservados.

📩 Contato: projetoscosanostra@gmail.com

🏆 “Do épico ao viral — criamos histórias que marcam época.”
