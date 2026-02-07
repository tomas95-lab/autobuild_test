# 🚀 Autobuild Web - 100% Free Cloud Deploy

Una interfaz web completamente gratuita para ejecutar **Autobuild** en la nube usando GitHub Actions.

> ⚡ **Deploy en 5 minutos** | 💰 **$0/mes** | 🔒 **Seguro** | 📦 **Sin servidor backend**

![GitHub Actions](https://img.shields.io/badge/GitHub-Actions-2088FF?logo=github-actions&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Enabled-2496ED?logo=docker&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)
![Free](https://img.shields.io/badge/Cost-$0/month-success)

## 🚀 Características

- ✅ **100% GRATUITO** - Deploy en Vercel + GitHub Actions
- 🎨 Interfaz web moderna y responsive
- 🔄 Ejecución en la nube vía GitHub Actions
- 📊 Monitoreo en tiempo real de workflows
- 📦 Sin base de datos necesaria (usa GitHub como backend)
- 🔐 Seguro - API keys en GitHub Secrets

## 🏗️ Arquitectura

```
┌─────────────────┐
│   GitHub Pages  │  ← Frontend estático (HTML/CSS/JS)
│   (Frontend)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ GitHub Actions  │  ← Ejecuta autobuild.sh
│  (Execution)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  GitHub API     │  ← Obtiene logs y resultados
│   (Backend)     │
└─────────────────┘
```

## 📦 Stack Tecnológico

- **Frontend**: Vanilla JS + Tailwind CSS
- **Hosting Frontend**: GitHub Pages (gratis)
- **Execution**: GitHub Actions (2000 mins/mes gratis)
- **API**: GitHub REST API (gratis)
- **Storage**: GitHub Artifacts (gratis)

## 🎬 Demo Rápido

[![Watch Demo](https://img.shields.io/badge/▶️-Watch%20Demo-red?style=for-the-badge)](https://github.com/YOUR-USERNAME/autobuild-web)

```bash
# 1. Setup automático
./setup.sh   # Linux/Mac
# o
.\setup.ps1  # Windows

# 2. Push a GitHub
git push -u origin main

# 3. Accede a tu app
# https://YOUR-USERNAME.github.io/autobuild-web/
```

**¡Listo en 5 minutos!** ⏱️

## 🚀 Deploy Completo

### 1. Crear Repositorio

```bash
# 1. Crear repo en GitHub (público para GitHub Pages gratis)
# 2. Subir este código
git init
git add .
git commit -m "Initial commit: Autobuild Web"
git remote add origin https://github.com/TU-USUARIO/autobuild-web.git
git push -u origin main
```

### 2. Configurar GitHub Actions

1. Ve a **Settings** → **Secrets and variables** → **Actions**
2. Agrega estos secrets:
   - `GEMINI_API_KEY`: Tu API key de Gemini

### 3. Habilitar GitHub Pages

1. Ve a **Settings** → **Pages**
2. Source: **GitHub Actions**
3. Guarda

### 4. ¡Listo!

Tu app estará disponible en: `https://TU-USUARIO.github.io/autobuild-web/`

## 📝 Uso

### Interfaz Web

1. Sube un archivo ZIP con tu task (debe contener `env/`, `verify/`, `prompt`)
2. Selecciona el modo de ejecución (feedback, verify, audit, etc.)
3. Haz clic en "Run Autobuild"
4. Monitorea el progreso en tiempo real
5. Descarga los logs cuando termine

### API REST (opcional)

```bash
# Trigger workflow
curl -X POST https://api.github.com/repos/TU-USUARIO/autobuild-web/actions/workflows/autobuild.yml/dispatches \
  -H "Authorization: token GITHUB_PAT" \
  -d '{"ref":"main","inputs":{"mode":"verify","task_url":"https://example.com/task.zip"}}'

# Check status
curl https://api.github.com/repos/TU-USUARIO/autobuild-web/actions/runs/WORKFLOW_ID
```

## 🔧 Desarrollo Local

```bash
# Instalar dependencias (opcional para testing)
npm install

# Servir frontend localmente
npx http-server public -p 8080

# Abrir en navegador
open http://localhost:8080
```

## 📂 Estructura del Proyecto

```
autobuild-web-free/
├── .github/
│   └── workflows/
│       └── autobuild.yml        # GitHub Actions workflow
├── public/
│   ├── index.html               # Frontend app
│   ├── app.js                   # Frontend logic
│   └── styles.css               # Estilos
├── scripts/
│   └── process-task.sh          # Script procesador para Actions
├── package.json                 # Metadata
└── README.md
```

## 🎯 Modos Disponibles

| Modo | Descripción |
|------|-------------|
| `feedback` | AI solves task con análisis |
| `verify` | AI intenta resolver (flujo cliente) |
| `audit` | Analiza calidad del task |
| `solution` | Ejecuta solución pre-hecha |
| `solution_verify` | Verifica solución antes/después |
| `auto_review` | Review completo |

## 💰 Costos (GRATIS)

- ✅ GitHub Pages: **GRATIS** (ilimitado para repos públicos)
- ✅ GitHub Actions: **2000 minutos/mes GRATIS**
- ✅ GitHub Storage: **500 MB artifacts GRATIS**
- ✅ GitHub API: **5000 requests/hora GRATIS**

**Total: $0/mes** 💸

## 🔒 Seguridad

- ✅ API keys en GitHub Secrets (nunca expuestas)
- ✅ Repo público pero secrets privados
- ✅ Workflows solo ejecutables por propietario
- ✅ Rate limiting automático de GitHub
- ✅ Sin base de datos = sin vulnerabilidades DB

## 🤝 Contribuir

¡Pull requests son bienvenidos!

## 📄 Licencia

MIT License - Usa como quieras

## 🆘 Soporte

- 📖 [Documentación Autobuild](../autobuild/README.md)
- 🐛 [Report Issues](https://github.com/TU-USUARIO/autobuild-web/issues)
- 💬 [Discussions](https://github.com/TU-USUARIO/autobuild-web/discussions)

---

**Made with ❤️ for the Autobuild community**
