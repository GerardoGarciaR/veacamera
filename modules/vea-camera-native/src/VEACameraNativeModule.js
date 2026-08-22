import { requireNativeModule } from 'expo-modules-core';

const VEACameraNative = requireNativeModule('VEACameraNative');

export function isMultiCamSupported() {
    return VEACameraNative.isMultiCamSupported();
}

export default VEACameraNative;