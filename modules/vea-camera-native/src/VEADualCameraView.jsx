import React from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';
import { requireNativeView } from 'expo';

let NativeDualCameraView = null;

if (Platform.OS === 'ios') {
  NativeDualCameraView = requireNativeView('VEACameraNative', 'VEADualCameraView');
}

export default function VEADualCameraView(props) {
  if (Platform.OS !== 'ios' || !NativeDualCameraView) {
    return (
      <View style={[styles.fallback, props.style]}>
        <Text style={styles.title}>MultiCam nativo de iOS</Text>
        <Text style={styles.body}>Compila un Development Build para usar esta vista.</Text>
      </View>
    );
  }

  return <NativeDualCameraView {...props} />;
}

const styles = StyleSheet.create({
  fallback: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    backgroundColor: '#050609',
  },
  title: { color: '#fff', fontSize: 22, fontWeight: '800' },
  body: { color: 'rgba(255,255,255,0.6)', marginTop: 8, textAlign: 'center' },
});
