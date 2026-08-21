# Roadmap técnico — VEA Camera

## Fase 1 — Dual Preview
Estado: starter implementado.

Objetivo: comprobar estabilidad y costo de hardware de `AVCaptureMultiCamSession` en iPhone real antes de añadir codificación.

## Fase 2 — Recorder/Compositor

Pipeline propuesto:

```text
Back AVCaptureVideoDataOutput ──────┐
                                    │
Front AVCaptureVideoDataOutput ─────┼─► Compositor Core Image / Metal
                                    │        │
Logo PNG ────────────────────────────┤        ├─► frame final 1080×1920
                                    │        │
Subtítulo estable ──────────────────┘        ▼
                                         AVAssetWriter
                                              │
Microphone AVCaptureAudioDataOutput ──────────┤
                                              ▼
                                           MP4 final
```

Mantener simultáneamente una ruta MASTER sin overlays para conservar material reutilizable.

## Fase 3 — Speech

- Capturar PCM del mismo micrófono usado por el video.
- Alimentar `SpeechAnalyzer`/`SpeechTranscriber`.
- Mostrar hipótesis/provisional en UI.
- Solo quemar texto estabilizado en el compositor, con un pequeño buffer configurable.
- Guardar transcript y timestamps para SRT/VTT.
