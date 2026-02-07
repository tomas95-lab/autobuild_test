# Quick Start Guide

## 🎯 Para Usuarios (Cómo Usar)

### 1. Acceder a la Web App
Visita: `https://TU-USUARIO.github.io/autobuild-web/`

### 2. Configurar Token (Primera Vez)
1. Crea un GitHub Personal Access Token:
   - Ve a https://github.com/settings/tokens
   - Click "Generate new token (classic)"
   - Selecciona scopes: `repo` y `workflow`
   - Copia el token
2. Pega el token cuando la app te lo pida
3. Se guarda en tu navegador (localStorage)

### 3. Preparar tu Task
Tu task debe ser un ZIP con esta estructura:
```
task.zip
├── env/
│   └── Dockerfile
├── verify/
│   ├── verify.sh
│   └── command
└── prompt
```

### 4. Ejecutar
1. Sube el ZIP
2. Dale un nombre único (ej: `mi-task-123`)
3. Selecciona modo (verify, feedback, audit, etc.)
4. Click "Run Autobuild"
5. Espera 5-15 minutos
6. Descarga los logs cuando termine

---

## 🔧 Para Admins (Cómo Deployar)

### Setup Rápido (5 minutos)

```bash
# 1. Crear repo público en GitHub
# Nombre sugerido: autobuild-web

# 2. Clonar este código
git clone https://github.com/TU-USUARIO/autobuild-web.git
cd autobuild-web

# 3. Copiar autobuild scripts (ajusta el path)
mkdir -p autobuild
cp -r ../autobuild/scripts autobuild/
cp -r ../autobuild/prompts autobuild/

# 4. Actualizar config en public/app.js
# Edita líneas 2-4 con tu username y repo

# 5. Commit y push
git add .
git commit -m "Initial setup"
git push origin main
```

### Configurar GitHub

1. **Secrets** (Settings → Secrets → Actions):
   - Agregar `GEMINI_API_KEY`

2. **Pages** (Settings → Pages):
   - Source: "GitHub Actions"
   - Save

3. **Esperá 2 minutos** para el primer deploy

### URLs Resultantes
- Web App: `https://TU-USUARIO.github.io/autobuild-web/`
- Actions: `https://github.com/TU-USUARIO/autobuild-web/actions`

---

## 💰 Costos

**GRATIS TOTAL:**
- GitHub Pages: ✅ Gratis (repos públicos)
- GitHub Actions: ✅ 2000 min/mes gratis
- Storage: ✅ 500 MB gratis
- Estimado: **~130-400 ejecuciones/mes GRATIS**

---

## 🐛 Problemas Comunes

### "Workflow no se ejecuta"
- ✅ Verificá que el token tenga scope `workflow`
- ✅ Revisá que GEMINI_API_KEY esté en Secrets

### "Task inválido"
- ✅ Verificá estructura del ZIP
- ✅ Dockerfile debe tener ese nombre exacto
- ✅ prompt debe estar sin extensión

### "Docker build falla"
- ✅ Dockerfile debe ser Debian-based
- ✅ Debe tener Node.js 20+
- ✅ No debe tener USER, CMD, o ENTRYPOINT

---

## 📚 Más Info

- [README completo](./README.md)
- [Guía de deploy](./DEPLOY.md)
- [Docs de Autobuild](../autobuild/README.md)
