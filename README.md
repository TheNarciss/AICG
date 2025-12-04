# 🎨 WebGPU Interactive Scene Editor

**Status**: 🚧 En construction

## 📁 Structure du Projet

```
webgpu-scene-editor/
├── index.html                    # ⏳ À créer - Application principale
├── shaders/                      # ✅ Shaders WGSL
│   ├── raymarch_basic.wgsl      # ⭐ Shader principal à modifier
│   ├── raymarch_glass.wgsl
│   ├── perlin_noise.wgsl
│   ├── fbm_perlin_noise.wgsl
│   ├── simple_noise.wgsl
│   ├── mouse.wgsl
│   └── manifest.json
├── assets/                       # 📸 Screenshots et ressources
├── .gitignore                    # ✅ Configuration Git
├── .nojekyll                     # ✅ Configuration GitHub Pages
└── README.md                     # 📝 Ce fichier

```

## 🎯 Objectifs du Projet

Ce projet transforme un viewer WebGPU Shadertoy en éditeur de scène 3D interactif avec :

1. **Scene Uniforms (35%)** : Système de buffers GPU pour contrôler les primitives 3D
2. **UI Interactive (30%)** : Panneau de contrôle avec sliders et color pickers
3. **Déploiement (20%)** : GitHub Pages + Documentation professionnelle
4. **Bonus Gizmo (15%)** : Click-to-select et manipulation 3D

## 📚 Documentation Complète

- **[PLAN_COMPLET_PROJET.md](../outputs/PLAN_COMPLET_PROJET.md)** : Guide étape par étape avec état de l'art
- **[ARCHITECTURE_PROJET.md](../outputs/ARCHITECTURE_PROJET.md)** : Architecture détaillée et flux de données

## 🚀 Prochaines Étapes

1. [ ] Créer `index.html` de base (copier depuis Lecture04)
2. [ ] Ajouter le système de Scene Buffer (Phase 1)
3. [ ] Créer l'UI Scene Editor (Phase 2)
4. [ ] Déployer sur GitHub Pages (Phase 3)
5. [ ] Implémenter le click-to-select (Phase 4)

## 🔧 Technologies

- **WebGPU** : API de rendu GPU moderne
- **WGSL** : WebGPU Shading Language
- **JavaScript (ES6+)** : Logique applicative
- **Tailwind CSS** : Styling
- **CodeMirror 5** : Éditeur de code

## 📖 Ressources

- [WGSL Spec](https://www.w3.org/TR/WGSL/)
- [WebGPU Fundamentals](https://webgpufundamentals.org/)
- [Inigo Quilez - SDFs](https://iquilezles.org/articles/)

---

**Note** : Ce projet est en cours de développement. Suivre les documents de planification pour l'implémentation.
