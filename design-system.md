# Design System - TracciaFood (Stile Aurora Glassmorphism)

## 1. Filosofia Visiva
L'interfaccia deve seguire lo stile "Glassmorphism Soft" con uno sfondo dinamico "Aurora". L'obiettivo è un look premium, scuro, profondo e fluttuante, ma senza essere stancante per gli occhi. L'app deve essere assolutamente responsive (mobile-first).

## 2. Palette Colori e Sfondo (CSS)
- **Sfondo Base**: Colore `#0f172a`.
- **Effetto Aurora**: Il body deve avere uno sfondo con `radial-gradient` per creare sfumature di viola (`rgba(139, 92, 246, 0.15)`), blu (`rgba(59, 130, 246, 0.15)`) e rosa (`rgba(236, 72, 153, 0.1)`).
- **Elementi Vetro (Card, Navbar)**: Sfondo semitrasparente chiaro (`rgba(255, 255, 255, 0.05)`).
- **Bordi**: Bordi luminosi molto sottili (`1px solid rgba(255, 255, 255, 0.1)`).
- **Testo**: Bianco puro (`#f8fafc`) o grigio chiaro (`#cbd5e1`).
- **Accento (Pulsanti)**: Viola/Lilla luminoso (`#a855f7`).

## 3. Regole CSS Obbligatorie (Glassmorphism)
Per ogni componente "Card" o "Navbar", applica la classe `.glass-panel` che contiene:
```css
background: rgba(255, 255, 255, 0.05);
backdrop-filter: blur(16px);
-webkit-backdrop-filter: blur(16px);
border: 1px solid rgba(255, 255, 255, 0.1);
border-radius: 24px;
box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.3);