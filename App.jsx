import React, { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Modal,
  Platform,
  Pressable,
  SafeAreaView,
  StatusBar,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';
import {
  useCameraPermissions,
  useMicrophonePermissions,
} from 'expo-camera';
import * as ImagePicker from 'expo-image-picker';

import VEADualCameraView from './modules/vea-camera-native/src/VEADualCameraView';
import { isMultiCamSupported } from './modules/vea-camera-native/src/VEACameraNativeModule';

const BRAND = {
  church: 'VEA Comunidad Cristiana',
  pastor: 'P.S. Mauricio Sánchez Scott',
  website: 'www.iglesiavea.com',
};

function formatDuration(totalSeconds) {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

export default function App() {
  const [cameraPermission, requestCameraPermission] = useCameraPermissions();
  const [microphonePermission, requestMicrophonePermission] = useMicrophonePermissions();

  const [support, setSupport] = useState(null);
  const [nativeStatus, setNativeStatus] = useState('Esperando permisos');
  const [nativeError, setNativeError] = useState('');

  // Camera-operator settings. Empty sermonTitle intentionally means:
  // keep the title slot blank for post-production.
  const [sermonTitle, setSermonTitle] = useState('');
  const [frontCameraVisible, setFrontCameraVisible] = useState(true);
  const [coverImageUri, setCoverImageUri] = useState('');
  const [settingsVisible, setSettingsVisible] = useState(false);

  const [recordingRequested, setRecordingRequested] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [lastMessage, setLastMessage] = useState('');

  const cameraGranted = cameraPermission?.granted === true;
  const microphoneGranted = microphonePermission?.granted === true;

  useEffect(() => {
    if (Platform.OS !== 'ios' || !cameraGranted) return;

    try {
      const supported = isMultiCamSupported();
      setSupport(supported);
      setNativeStatus(supported ? 'Preparando MultiCam…' : 'MultiCam no disponible');
    } catch (error) {
      setSupport(false);
      setNativeError(String(error?.message ?? error));
    }
  }, [cameraGranted]);

  useEffect(() => {
    if (!isRecording) {
      setElapsedSeconds(0);
      return undefined;
    }

    const startedAt = Date.now();
    const timer = setInterval(() => {
      setElapsedSeconds(Math.floor((Date.now() - startedAt) / 1000));
    }, 500);

    return () => clearInterval(timer);
  }, [isRecording]);

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

  async function chooseCoverImage() {
    const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!permission.granted) {
      Alert.alert(
        'Permiso de Fotos',
        'VEA Camera necesita acceso a Fotos para seleccionar la portada de la prédica.'
      );
      return;
    }

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsEditing: true,
      aspect: [1, 1],
      quality: 1,
    });

    if (!result.canceled && result.assets?.[0]?.uri) {
      setCoverImageUri(result.assets[0].uri);
    }
  }

  async function toggleRecording() {
    if (isRecording || recordingRequested) {
      setRecordingRequested(false);
      return;
    }

    if (!microphoneGranted) {
      const result = await requestMicrophonePermission();
      if (!result?.granted) {
        Alert.alert('Micrófono requerido', 'Autoriza el micrófono para grabar la prédica con audio.');
        return;
      }
    }

    setLastMessage('');
    setRecordingRequested(true);
  }

  if (Platform.OS !== 'ios') {
    return (
      <SafeAreaView style={styles.fallbackRoot}>
        <StatusBar barStyle="light-content" />
        <View style={styles.permissionCard}>
          <Text style={styles.permissionEyebrow}>VEA CAMERA</Text>
          <Text style={styles.permissionTitle}>La cámara dual vive en iOS nativo.</Text>
          <Text style={styles.permissionBody}>
            Este compositor usa AVCaptureMultiCamSession y debe probarse en un iPhone mediante un Development Build.
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  if (!cameraPermission || !microphonePermission) {
    return (
      <View style={styles.loadingRoot}>
        <ActivityIndicator size="large" color="#ffffff" />
        <Text style={styles.loadingText}>Preparando VEA Camera…</Text>
      </View>
    );
  }

  if (!cameraGranted || !microphoneGranted) {
    return (
      <SafeAreaView style={styles.permissionRoot}>
        <StatusBar barStyle="light-content" />
        <View style={styles.permissionGlow} />
        <View style={styles.permissionCard}>
          <Text style={styles.permissionEyebrow}>VEA CAMERA</Text>
          <Text style={styles.permissionTitle}>Tu estudio VEA, en el iPhone.</Text>
          <Text style={styles.permissionBody}>
            Necesitamos cámara y micrófono para mostrar las dos cámaras y grabar la prédica con audio.
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
    <SafeAreaView style={styles.root}>
      <StatusBar barStyle="light-content" />

      <View style={styles.header}>
        <View>
          <Text style={styles.appEyebrow}>VEA CAMERA</Text>
          <Text style={styles.appTitle}>Studio</Text>
        </View>

        <View style={styles.statusPill}>
          <View style={[styles.statusDot, support === false && styles.statusDotError]} />
          <Text style={styles.statusPillText} numberOfLines={1}>
            {support === false ? 'MultiCam no disponible' : nativeStatus}
          </Text>
        </View>
      </View>

      <View style={styles.stageShell}>
        <VEADualCameraView
          style={StyleSheet.absoluteFill}
          pipDiameter={132}
          pipMargin={18}
          logoVisible
          logoWidthRatio={0.24}
          frontCameraVisible={frontCameraVisible}
          sermonTitle={sermonTitle}
          coverImageUri={coverImageUri || ''}
          recording={recordingRequested}
          tiktokSafeRightRatio={0.16}
          tiktokSafeBottomRatio={0.18}
          showTikTokSafeZone={false}
          onReady={(event) => {
            const hardwareCost = event?.nativeEvent?.hardwareCost;
            setNativeStatus(
              typeof hardwareCost === 'number'
                ? `MultiCam · ${(hardwareCost * 100).toFixed(0)}%`
                : 'MultiCam listo'
            );
            setNativeError('');
          }}
          onError={(event) => {
            const message = event?.nativeEvent?.message ?? 'Error desconocido de cámara';
            setNativeError(message);
            setNativeStatus('Error MultiCam');
          }}
          onRecordingStarted={() => {
            setIsRecording(true);
            setLastMessage('Grabando en 1080 × 1920');
          }}
          onRecordingFinished={(event) => {
            setIsRecording(false);
            setRecordingRequested(false);
            if (event?.nativeEvent?.savedToPhotos) {
              setLastMessage('✓ Video guardado en Fotos');
            } else {
              setLastMessage('Grabación terminada');
            }
          }}
          onRecordingError={(event) => {
            const message = event?.nativeEvent?.message ?? 'No fue posible grabar el video.';
            setIsRecording(false);
            setRecordingRequested(false);
            setLastMessage('');
            Alert.alert('Grabación', message);
          }}
        />

        <Pressable
          disabled={isRecording}
          onPress={() => setSettingsVisible(true)}
          style={({ pressed }) => [
            styles.settingsButton,
            pressed && !isRecording && styles.settingsButtonPressed,
            isRecording && styles.settingsButtonDisabled,
          ]}
        >
          <Text style={styles.settingsIcon}>⚙︎</Text>
        </Pressable>

        {isRecording ? (
          <View style={styles.recordingBadge} pointerEvents="none">
            <View style={styles.recordingDot} />
            <Text style={styles.recordingBadgeText}>REC {formatDuration(elapsedSeconds)}</Text>
          </View>
        ) : null}
      </View>

      <View style={styles.controls}>
        <Pressable
          onPress={toggleRecording}
          style={({ pressed }) => [styles.recOuter, pressed && styles.recOuterPressed]}
          accessibilityRole="button"
          accessibilityLabel={isRecording ? 'Detener grabación' : 'Iniciar grabación'}
        >
          <View style={[styles.recInner, isRecording && styles.stopInner]} />
        </Pressable>

        <View style={styles.controlCopy}>
          <Text style={styles.controlTitle}>
            {isRecording ? `Grabando · ${formatDuration(elapsedSeconds)}` : 'Listo para grabar'}
          </Text>
          <Text style={styles.controlSubtitle} numberOfLines={2}>
            {lastMessage || 'El video final incluye cámaras, logo, portada y rótulos VEA.'}
          </Text>
          {nativeError ? <Text style={styles.errorText}>{nativeError}</Text> : null}
        </View>
      </View>

      <Modal
        visible={settingsVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setSettingsVisible(false)}
      >
        <Pressable style={styles.modalBackdrop} onPress={() => setSettingsVisible(false)}>
          <Pressable style={styles.settingsSheet} onPress={() => {}}>
            <View style={styles.sheetHandle} />

            <View style={styles.sheetHeader}>
              <View>
                <Text style={styles.sheetEyebrow}>CONFIGURACIÓN DE SALIDA</Text>
                <Text style={styles.sheetTitle}>Predicación</Text>
              </View>
              <Pressable style={styles.closeButton} onPress={() => setSettingsVisible(false)}>
                <Text style={styles.closeButtonText}>×</Text>
              </Pressable>
            </View>

            <Text style={styles.fieldLabel}>Título de la prédica</Text>
            <TextInput
              value={sermonTitle}
              onChangeText={setSermonTitle}
              placeholder="Ej. Ventanas Rotas"
              placeholderTextColor="rgba(255,255,255,0.32)"
              style={styles.titleInput}
              autoCapitalize="sentences"
              returnKeyType="done"
              maxLength={52}
            />
            <Text style={styles.fieldHint}>
              Si lo dejas vacío, “Estas viendo” permanece y el espacio del título queda libre para postproducción.
            </Text>

            <View style={styles.settingRow}>
              <View style={styles.settingTextBlock}>
                <Text style={styles.settingTitle}>Cámara frontal flotante</Text>
                <Text style={styles.settingDescription}>
                  Mostrar u ocultar el círculo de la cámara frontal en preview y en el MP4.
                </Text>
              </View>
              <Switch
                value={frontCameraVisible}
                onValueChange={setFrontCameraVisible}
                trackColor={{ false: '#3b3d43', true: '#34c759' }}
                thumbColor="#ffffff"
              />
            </View>

            <Text style={styles.fieldLabel}>Cover de la prédica / podcast</Text>
            <View style={styles.coverRow}>
              <View style={styles.coverPreview}>
                {coverImageUri ? (
                  <Image source={{ uri: coverImageUri }} style={styles.coverPreviewImage} />
                ) : (
                  <Text style={styles.coverPlaceholder}>PORTADA</Text>
                )}
              </View>

              <View style={styles.coverActions}>
                <Pressable style={styles.chooseCoverButton} onPress={chooseCoverImage}>
                  <Text style={styles.chooseCoverButtonText}>
                    {coverImageUri ? 'Cambiar portada' : 'Elegir desde Fotos'}
                  </Text>
                </Pressable>
                {coverImageUri ? (
                  <Pressable style={styles.removeCoverButton} onPress={() => setCoverImageUri('')}>
                    <Text style={styles.removeCoverButtonText}>Quitar portada</Text>
                  </Pressable>
                ) : null}
              </View>
            </View>

            <View style={styles.fixedBrandCard}>
              <Text style={styles.fixedBrandLabel}>RÓTULOS FIJOS</Text>
              <Text style={styles.fixedBrandText}>{BRAND.church}</Text>
              <Text style={styles.fixedBrandText}>{BRAND.pastor}</Text>
              <Text style={styles.fixedBrandText}>{BRAND.website}</Text>
            </View>

            <Pressable style={styles.doneButton} onPress={() => setSettingsVisible(false)}>
              <Text style={styles.doneButtonText}>Listo</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#050506',
    paddingHorizontal: 14,
  },
  header: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
    paddingHorizontal: 4,
  },
  appEyebrow: {
    color: 'rgba(255,255,255,0.50)',
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 2.2,
  },
  appTitle: {
    color: '#fff',
    fontSize: 23,
    fontWeight: '800',
    letterSpacing: -0.6,
  },
  statusPill: {
    maxWidth: '58%',
    height: 31,
    paddingHorizontal: 11,
    borderRadius: 16,
    backgroundColor: 'rgba(255,255,255,0.075)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.16)',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
  },
  statusDot: {
    width: 7,
    height: 7,
    borderRadius: 4,
    backgroundColor: '#34c759',
  },
  statusDotError: { backgroundColor: '#ff453a' },
  statusPillText: {
    color: 'rgba(255,255,255,0.76)',
    fontSize: 11,
    fontWeight: '700',
    flexShrink: 1,
  },
  stageShell: {
    width: '100%',
    aspectRatio: 9 / 16,
    alignSelf: 'center',
    position: 'relative',
    borderRadius: 24,
    overflow: 'hidden',
    backgroundColor: '#000',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.15)',
  },
  settingsButton: {
    position: 'absolute',
    right: 14,
    top: 14,
    width: 48,
    height: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(14,14,16,0.56)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.22)',
  },
  settingsButtonPressed: { transform: [{ scale: 0.94 }] },
  settingsButtonDisabled: { opacity: 0.35 },
  settingsIcon: {
    color: '#fff',
    fontSize: 27,
    lineHeight: 30,
  },
  recordingBadge: {
    position: 'absolute',
    left: 14,
    top: 14,
    height: 32,
    borderRadius: 16,
    paddingHorizontal: 11,
    backgroundColor: 'rgba(8,8,10,0.64)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.18)',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
  },
  recordingDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#ff3b30',
  },
  recordingBadgeText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 0.7,
  },
  controls: {
    flex: 1,
    minHeight: 104,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 18,
    paddingHorizontal: 8,
  },
  recOuter: {
    width: 72,
    height: 72,
    borderRadius: 36,
    borderWidth: 4,
    borderColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  recOuterPressed: { transform: [{ scale: 0.95 }] },
  recInner: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: '#ff3b30',
  },
  stopInner: {
    width: 30,
    height: 30,
    borderRadius: 7,
  },
  controlCopy: {
    flex: 1,
    maxWidth: 270,
  },
  controlTitle: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '800',
  },
  controlSubtitle: {
    color: 'rgba(255,255,255,0.50)',
    fontSize: 11.5,
    lineHeight: 16,
    marginTop: 3,
  },
  errorText: {
    color: '#ff9b93',
    fontSize: 11,
    marginTop: 4,
  },
  modalBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.58)',
    justifyContent: 'flex-end',
  },
  settingsSheet: {
    paddingHorizontal: 20,
    paddingTop: 10,
    paddingBottom: 28,
    borderTopLeftRadius: 30,
    borderTopRightRadius: 30,
    backgroundColor: '#151518',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.13)',
  },
  sheetHandle: {
    width: 42,
    height: 5,
    borderRadius: 3,
    alignSelf: 'center',
    backgroundColor: 'rgba(255,255,255,0.20)',
    marginBottom: 13,
  },
  sheetHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 18,
  },
  sheetEyebrow: {
    color: 'rgba(255,255,255,0.42)',
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 1.6,
  },
  sheetTitle: {
    color: '#fff',
    fontSize: 26,
    fontWeight: '800',
    letterSpacing: -0.7,
    marginTop: 2,
  },
  closeButton: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  closeButtonText: {
    color: '#fff',
    fontSize: 27,
    lineHeight: 28,
  },
  fieldLabel: {
    color: 'rgba(255,255,255,0.72)',
    fontSize: 12,
    fontWeight: '800',
    marginBottom: 7,
  },
  titleInput: {
    minHeight: 50,
    borderRadius: 15,
    paddingHorizontal: 15,
    color: '#fff',
    fontSize: 16,
    backgroundColor: 'rgba(255,255,255,0.07)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
  },
  fieldHint: {
    color: 'rgba(255,255,255,0.38)',
    fontSize: 10.5,
    lineHeight: 15,
    marginTop: 7,
    marginBottom: 17,
  },
  settingRow: {
    minHeight: 72,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingVertical: 10,
    paddingHorizontal: 13,
    borderRadius: 16,
    backgroundColor: 'rgba(255,255,255,0.055)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.11)',
    marginBottom: 18,
  },
  settingTextBlock: { flex: 1 },
  settingTitle: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '800',
  },
  settingDescription: {
    color: 'rgba(255,255,255,0.43)',
    fontSize: 10.5,
    lineHeight: 15,
    marginTop: 3,
  },
  coverRow: {
    flexDirection: 'row',
    gap: 14,
    alignItems: 'center',
    marginBottom: 18,
  },
  coverPreview: {
    width: 82,
    height: 82,
    borderRadius: 14,
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.055)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.13)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  coverPreviewImage: { width: '100%', height: '100%' },
  coverPlaceholder: {
    color: 'rgba(255,255,255,0.26)',
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 1.1,
  },
  coverActions: { flex: 1, gap: 8 },
  chooseCoverButton: {
    minHeight: 41,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#ffffff',
  },
  chooseCoverButtonText: {
    color: '#101012',
    fontSize: 12,
    fontWeight: '800',
  },
  removeCoverButton: {
    minHeight: 36,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,69,58,0.10)',
  },
  removeCoverButtonText: {
    color: '#ff8a82',
    fontSize: 11,
    fontWeight: '800',
  },
  fixedBrandCard: {
    borderRadius: 15,
    padding: 13,
    backgroundColor: 'rgba(255,255,255,0.045)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.10)',
    marginBottom: 17,
  },
  fixedBrandLabel: {
    color: 'rgba(255,255,255,0.35)',
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 1.4,
    marginBottom: 5,
  },
  fixedBrandText: {
    color: 'rgba(255,255,255,0.72)',
    fontSize: 12,
    lineHeight: 17,
  },
  doneButton: {
    minHeight: 49,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#0a84ff',
  },
  doneButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '900',
  },
  loadingRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#050506',
    gap: 13,
  },
  loadingText: {
    color: 'rgba(255,255,255,0.65)',
    fontSize: 14,
    fontWeight: '600',
  },
  permissionRoot: {
    flex: 1,
    padding: 24,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#050506',
    overflow: 'hidden',
  },
  permissionGlow: {
    position: 'absolute',
    width: 320,
    height: 320,
    borderRadius: 160,
    backgroundColor: 'rgba(10,132,255,0.16)',
    top: 60,
    right: -150,
  },
  permissionCard: {
    width: '100%',
    maxWidth: 460,
    borderRadius: 28,
    padding: 25,
    backgroundColor: 'rgba(255,255,255,0.065)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
  },
  permissionEyebrow: {
    color: 'rgba(255,255,255,0.48)',
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 2,
  },
  permissionTitle: {
    color: '#fff',
    fontSize: 28,
    lineHeight: 33,
    fontWeight: '800',
    marginTop: 10,
  },
  permissionBody: {
    color: 'rgba(255,255,255,0.60)',
    fontSize: 14,
    lineHeight: 21,
    marginTop: 11,
  },
  primaryButton: {
    minHeight: 52,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#fff',
    marginTop: 22,
  },
  primaryButtonText: {
    color: '#101012',
    fontSize: 15,
    fontWeight: '900',
  },
  permissionHint: {
    color: 'rgba(255,255,255,0.36)',
    fontSize: 11,
    textAlign: 'center',
    marginTop: 12,
  },
  fallbackRoot: {
    flex: 1,
    backgroundColor: '#050506',
    padding: 24,
    justifyContent: 'center',
  },
});
