import React, { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Platform,
  Pressable,
  SafeAreaView,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import {
  useCameraPermissions,
  useMicrophonePermissions,
} from 'expo-camera';

import VEADualCameraView from './modules/vea-camera-native/src/VEADualCameraView';
import { isMultiCamSupported } from './modules/vea-camera-native/src/VEACameraNativeModule';

export default function App() {
  const [cameraPermission, requestCameraPermission] = useCameraPermissions();
  const [microphonePermission, requestMicrophonePermission] = useMicrophonePermissions();
  const [support, setSupport] = useState(null);
  const [nativeStatus, setNativeStatus] = useState('Esperando permisos');
  const [nativeError, setNativeError] = useState('');

  const cameraGranted = cameraPermission?.granted === true;
  const microphoneGranted = microphonePermission?.granted === true;

  useEffect(() => {
    if (Platform.OS !== 'ios' || !cameraGranted) {
      return;
    }

    try {
      const supported = isMultiCamSupported();
      setSupport(supported);
      setNativeStatus(supported ? 'Preparando MultiCam…' : 'MultiCam no disponible');
    } catch (error) {
      setSupport(false);
      setNativeError(String(error?.message ?? error));
    }
  }, [cameraGranted]);

  const permissionSummary = useMemo(() => {
    if (!cameraPermission || !microphonePermission) return 'Consultando permisos…';
    if (cameraGranted && microphoneGranted) return 'Cámara y micrófono autorizados';
    if (cameraGranted) return 'Cámara autorizada · falta micrófono';
    return 'Necesitamos acceso a cámara y micrófono';
  }, [cameraPermission, microphonePermission, cameraGranted, microphoneGranted]);

  async function requestAllPermissions() {
    setNativeError('');
    const cameraResult = cameraGranted
      ? cameraPermission
      : await requestCameraPermission();

    if (cameraResult?.granted && !microphoneGranted) {
      await requestMicrophonePermission();
    }
  }

  if (Platform.OS !== 'ios') {
    return (
      <SafeAreaView style={styles.fallbackRoot}>
        <StatusBar barStyle="light-content" />
        <View style={styles.fallbackCard}>
          <Text style={styles.eyebrow}>VEA CAMERA · MVP 01</Text>
          <Text style={styles.fallbackTitle}>La cámara dual vive en iOS nativo.</Text>
          <Text style={styles.fallbackBody}>
            La interfaz Expo puede seguir siendo multiplataforma, pero este primer MVP usa
            AVCaptureMultiCamSession y debe probarse en un iPhone mediante un Development Build.
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  if (!cameraPermission || !microphonePermission) {
    return (
      <View style={styles.loadingRoot}>
        <ActivityIndicator size="large" />
        <Text style={styles.loadingText}>Preparando VEA Camera…</Text>
      </View>
    );
  }

  if (!cameraGranted) {
    return (
      <SafeAreaView style={styles.permissionRoot}>
        <StatusBar barStyle="light-content" />
        <View style={styles.permissionGlow} />
        <View style={styles.permissionCard}>
          <Text style={styles.brand}>VEA</Text>
          <Text style={styles.permissionTitle}>Nuestro pequeño estudio de bolsillo.</Text>
          <Text style={styles.permissionBody}>
            Para el preview dual necesitamos las cámaras. También pedimos micrófono desde ahora
            porque será la fuente de audio y transcripción en las siguientes fases.
          </Text>
          <Pressable style={styles.primaryButton} onPress={requestAllPermissions}>
            <Text style={styles.primaryButtonText}>Dar permisos</Text>
          </Pressable>
          <Text style={styles.permissionHint}>{permissionSummary}</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <View style={styles.root}>
      <StatusBar barStyle="light-content" />

      <VEADualCameraView
        style={StyleSheet.absoluteFill}
        pipDiameter={132}
        pipMargin={18}
        logoVisible
        logoWidthRatio={0.34}
        tiktokSafeRightRatio={0.16}
        tiktokSafeBottomRatio={0.18}
        showTikTokSafeZone={false}
        onReady={(event) => {
          const hardwareCost = event?.nativeEvent?.hardwareCost;
          setNativeStatus(
            typeof hardwareCost === 'number'
              ? `MultiCam activo · costo ${(hardwareCost * 100).toFixed(0)}%`
              : 'MultiCam activo'
          );
          setNativeError('');
        }}
        onError={(event) => {
          const message = event?.nativeEvent?.message ?? 'Error desconocido de cámara';
          setNativeError(message);
          setNativeStatus('No se pudo iniciar MultiCam');
        }}
      />

      <SafeAreaView style={styles.hud} pointerEvents="box-none">
        <View style={styles.topBar} pointerEvents="none">
          <View>
            <Text style={styles.eyebrow}>VEA CAMERA</Text>
            <Text style={styles.topTitle}>Dual Preview</Text>
          </View>
          <View style={styles.livePill}>
            <View style={styles.liveDot} />
            <Text style={styles.liveText}>MVP 01</Text>
          </View>
        </View>

        <View style={styles.spacer} />

        <View style={styles.bottomPanel}>
          <Text style={styles.statusLabel}>ESTADO NATIVO</Text>
          <Text style={styles.statusText}>{nativeStatus}</Text>
          {support === false ? (
            <Text style={styles.errorText}>
              Este dispositivo reportó que AVCaptureMultiCamSession no está disponible.
            </Text>
          ) : null}
          {nativeError ? <Text style={styles.errorText}>{nativeError}</Text> : null}
          <View style={styles.milestones}>
            <View style={styles.milestoneDone}>
              <Text style={styles.milestoneIcon}>✓</Text>
              <Text style={styles.milestoneText}>Dual Cam</Text>
            </View>
            <View style={styles.milestoneDone}>
              <Text style={styles.milestoneIcon}>✓</Text>
              <Text style={styles.milestoneText}>Marca VEA</Text>
            </View>
            <View style={styles.milestoneNext}>
              <Text style={styles.milestoneNextIcon}>2</Text>
              <Text style={styles.milestoneNextText}>Grabación MP4</Text>
            </View>
          </View>
          {!microphoneGranted ? (
            <Pressable style={styles.secondaryButton} onPress={requestMicrophonePermission}>
              <Text style={styles.secondaryButtonText}>Autorizar micrófono</Text>
            </Pressable>
          ) : null}
        </View>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#020305' },
  hud: { flex: 1, paddingHorizontal: 18, paddingTop: 8, paddingBottom: 12 },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingTop: 6,
  },
  eyebrow: {
    color: 'rgba(255,255,255,0.66)',
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 2.2,
  },
  topTitle: { color: '#fff', fontSize: 24, fontWeight: '800', marginTop: 2 },
  livePill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
    backgroundColor: 'rgba(0,0,0,0.42)',
    borderColor: 'rgba(255,255,255,0.16)',
    borderWidth: 1,
    paddingHorizontal: 12,
    height: 36,
    borderRadius: 18,
  },
  liveDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#ff453a' },
  liveText: { color: '#fff', fontSize: 12, fontWeight: '800', letterSpacing: 0.8 },
  spacer: { flex: 1 },
  bottomPanel: {
    borderRadius: 26,
    padding: 18,
    backgroundColor: 'rgba(12,13,16,0.72)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.15)',
  },
  statusLabel: {
    color: 'rgba(255,255,255,0.54)',
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 1.5,
  },
  statusText: { color: '#fff', fontSize: 18, fontWeight: '800', marginTop: 4 },
  errorText: { color: '#ffb4ab', fontSize: 12, lineHeight: 17, marginTop: 7 },
  milestones: { flexDirection: 'row', gap: 8, marginTop: 15, flexWrap: 'wrap' },
  milestoneDone: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 11,
    height: 32,
    borderRadius: 16,
    backgroundColor: 'rgba(73, 217, 143, 0.14)',
    borderWidth: 1,
    borderColor: 'rgba(73, 217, 143, 0.28)',
  },
  milestoneIcon: { color: '#6ee7a8', fontWeight: '900' },
  milestoneText: { color: '#eafff2', fontSize: 12, fontWeight: '700' },
  milestoneNext: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 11,
    height: 32,
    borderRadius: 16,
    backgroundColor: 'rgba(255,255,255,0.07)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.10)',
  },
  milestoneNextIcon: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '900',
    width: 18,
    height: 18,
    lineHeight: 18,
    textAlign: 'center',
    borderRadius: 9,
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  milestoneNextText: { color: 'rgba(255,255,255,0.74)', fontSize: 12, fontWeight: '700' },
  secondaryButton: {
    marginTop: 14,
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 14,
    backgroundColor: 'rgba(255,255,255,0.10)',
  },
  secondaryButtonText: { color: '#fff', fontWeight: '800' },
  loadingRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#06070a',
    gap: 14,
  },
  loadingText: { color: 'rgba(255,255,255,0.72)', fontSize: 15, fontWeight: '600' },
  permissionRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    backgroundColor: '#050609',
    overflow: 'hidden',
  },
  permissionGlow: {
    position: 'absolute',
    width: 300,
    height: 300,
    borderRadius: 150,
    backgroundColor: 'rgba(137, 92, 246, 0.18)',
    top: 80,
    right: -120,
  },
  permissionCard: {
    width: '100%',
    maxWidth: 440,
    borderRadius: 30,
    padding: 26,
    backgroundColor: 'rgba(255,255,255,0.07)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.13)',
  },
  brand: { color: '#fff', fontSize: 46, fontWeight: '900', letterSpacing: -2 },
  permissionTitle: { color: '#fff', fontSize: 27, lineHeight: 32, fontWeight: '800', marginTop: 12 },
  permissionBody: { color: 'rgba(255,255,255,0.68)', fontSize: 15, lineHeight: 22, marginTop: 12 },
  primaryButton: {
    minHeight: 54,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#fff',
    marginTop: 24,
  },
  primaryButtonText: { color: '#050609', fontSize: 16, fontWeight: '900' },
  permissionHint: { color: 'rgba(255,255,255,0.45)', fontSize: 12, textAlign: 'center', marginTop: 13 },
  fallbackRoot: { flex: 1, backgroundColor: '#050609', padding: 24, justifyContent: 'center' },
  fallbackCard: { borderRadius: 26, padding: 24, backgroundColor: '#111319' },
  fallbackTitle: { color: '#fff', fontSize: 26, lineHeight: 31, fontWeight: '800', marginTop: 10 },
  fallbackBody: { color: 'rgba(255,255,255,0.66)', fontSize: 15, lineHeight: 22, marginTop: 12 },
});
