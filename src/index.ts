import { NativeModules, Platform, TurboModuleRegistry, NativeEventEmitter } from "react-native"
import type { ImageResult, GalleryOptions, EditorOptions, SelectionChangeEvent } from "./types"

const LINKING_ERROR = `The package 'react-native-turbo-image-picker' doesn't seem to be linked. Make sure: \n\n` + Platform.select({ ios: "- You have run 'pod install'\n", default: "" }) + "- You rebuilt the app after installing the package\n" + "- You are not using Expo Go\n"

// Try to get Turbo Module first (New Architecture)
let NativeTurboImagePicker: any = null

try {
  // @ts-ignore - TurboModuleRegistry might not be available
  NativeTurboImagePicker = TurboModuleRegistry?.get?.("RNTurboImagePicker")
} catch (e) {
  // Turbo Module not available
}

// Fallback to Legacy Native Module (Old Architecture)
const LegacyModule = NativeModules.RNTurboImagePicker

// Use Turbo Module if available, otherwise use Legacy Module
const RNTurboImagePickerModule = NativeTurboImagePicker || LegacyModule

if (!RNTurboImagePickerModule) {
  throw new Error(LINKING_ERROR)
}

// Create event emitter
const eventEmitter = new NativeEventEmitter(RNTurboImagePickerModule)

export type { SelectionChangeEvent } from "./types"

export interface RNTurboImagePicker {
  openGallery(options?: GalleryOptions): Promise<ImageResult[]>
  openEditor(options: EditorOptions): Promise<ImageResult>
  openViewer(options: ViewerOptions): Promise<void>
  closeGallery(): Promise<boolean>
  addSelectionChangeListener(listener: (event: SelectionChangeEvent) => void): () => void
}

const TurboImagePicker: RNTurboImagePicker = {
  openGallery: async (options: GalleryOptions = {}): Promise<ImageResult[]> => {
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }

    // onSelectionChange 콜백이 있으면 임시 리스너 등록
    let subscription: any = null
    if (options.onSelectionChange) {
      subscription = eventEmitter.addListener("onSelectionChange", options.onSelectionChange)
    }

    try {
      // onSelectionChange는 네이티브로 전달하지 않음 (JavaScript에서 처리)
      const { onSelectionChange, ...nativeOptions } = options
      const result = await RNTurboImagePickerModule.openGallery(nativeOptions)
      return result
    } finally {
      // 갤러리가 닫히면 리스너 제거
      if (subscription) {
        subscription.remove()
      }
    }
  },

  openEditor: async (options: EditorOptions): Promise<ImageResult> => {
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNTurboImagePickerModule.openEditor(options)
  },

  openViewer: async (options: ViewerOptions): Promise<void> => {
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNTurboImagePickerModule.openViewer(options)
  },

  closeGallery: async (): Promise<boolean> => {
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }

    return RNTurboImagePickerModule.closeGallery()
  },

  addSelectionChangeListener: (listener: (event: SelectionChangeEvent) => void) => {
    const subscription = eventEmitter.addListener("onSelectionChange", listener)

    // Return cleanup function
    return () => {
      subscription.remove()
    }
  },
}

// Export info about which architecture is being used
export const isUsingTurboModule = !!NativeTurboImagePicker
export const isUsingLegacyModule = !!LegacyModule && !NativeTurboImagePicker

export default TurboImagePicker
