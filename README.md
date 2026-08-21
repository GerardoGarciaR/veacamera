# VEA Camera — MVP 01

Primer hito del “OBS de bolsillo” para VEA.

## Qué incluye hoy

- Expo SDK 57 / React Native 0.86.
- App vertical iOS.
- Permisos de cámara y micrófono.
- Módulo Expo local escrito en Swift.
- `AVCaptureMultiCamSession` para cámara trasera + frontal simultáneas.
- Cámara trasera a pantalla completa.
- Cámara frontal como PiP circular en la esquina superior derecha.
- Marca de agua de prueba `VEA` dentro de la vista nativa.
- Diagnóstico de `hardwareCost` y `systemPressureCost`.
- Fallback informativo en Web/otras plataformas.

> En este MVP **todavía no se graba un MP4**. Primero validamos que la captura dual funcione estable en el iPhone real. La fase 2 agregará el pipeline de grabación/composición.

## Requisitos en la Mac

- macOS con Xcode compatible con Expo SDK 57 (Xcode 26.4+ según la referencia actual de Expo).
- Node.js 22.13 o superior.
- CocoaPods disponible.
- iPhone conectado por USB o preparado para desarrollo inalámbrico.
- Developer Mode activado en el iPhone.

No necesitas una membresía pagada de Apple Developer para probar en tu propio dispositivo con un Personal Team; la firma gratuita tiene las limitaciones habituales de desarrollo.

## Instalación

```bash
cd VEA-Camera-MVP-01
npm install
npx expo install --fix
npx expo prebuild --platform ios --clean
npx expo run:ios --device
```

Al ejecutar `expo run:ios --device`, elige tu iPhone.

Si Xcode te pide firma:

1. Abre `ios/VEACamera.xcworkspace`.
2. Selecciona el target de la app.
3. En **Signing & Capabilities**, activa **Automatically manage signing**.
4. En **Team**, selecciona tu **Personal Team**.
5. Vuelve a ejecutar desde Xcode o con `npx expo run:ios --device`.

## Qué deberías ver

1. Pantalla solicitando permisos.
2. Video de la cámara trasera ocupando toda la pantalla.
3. Cámara frontal dentro de un círculo en la parte superior derecha.
4. Marca `VEA` en la parte superior izquierda.
5. En el panel inferior: `MultiCam activo` y el costo de hardware reportado por AVFoundation.

## Si aparece “MultiCam no disponible”

El módulo consulta directamente `AVCaptureMultiCamSession.isMultiCamSupported`. No emula dos cámaras con dos instancias de `expo-camera`.

## Arquitectura inicial

```text
App.jsx
  │
  ├─ permisos con expo-camera
  │
  └─ VEADualCameraView (React Native)
           │
           ▼
     Expo Modules API
           │
           ▼
 VEACameraNativeModule.swift
           │
           ▼
 AVCaptureMultiCamSession
       ┌───────┴───────┐
       ▼               ▼
  cámara trasera   cámara frontal
       │               │
 fullscreen         círculo PiP
       └───────┬───────┘
               ▼
          preview nativo
```

## Fases siguientes

### MVP 02 — Grabación real
- `AVCaptureVideoDataOutput` para obtener frames de ambas cámaras.
- Audio de micrófono.
- Composición 1080×1920.
- Cámara frontal recortada a círculo.
- Logo PNG real configurable.
- `AVAssetWriter` para generar MP4.
- MASTER limpio + FINAL compuesto.

### MVP 03 — Subtítulos
- `SpeechAnalyzer` / `SpeechTranscriber` en iOS compatible.
- Texto provisional en vivo.
- Texto estabilizado para el archivo final.
- Exportación SRT/VTT.

### MVP 04 — Mini OBS
- Escenas/presets.
- Posición y tamaño del PiP.
- Logo seleccionable.
- Zoom, flash y exposición.
- Medidores de audio.
- Galería y compartir.
