import { Platform } from 'react-native';
import { requireOptionalNativeModule } from 'expo';

const nativeModule = Platform.OS === 'ios'
  ? requireOptionalNativeModule('VEACameraNative')
  : null;

export function isMultiCamSupported() {
  return nativeModule?.isMultiCamSupported?.() ?? false;
}
