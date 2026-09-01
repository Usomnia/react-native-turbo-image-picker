import { NativeModules, Platform, TurboModuleRegistry, NativeEventEmitter } from "react-native"
import type { ImageResult, GalleryOptions, EditorOptions, SelectionChangeEvent, ViewerOptions } from "./types"

const LINKING_ERROR = `The package 'react-native-turbo-image-picker' doesn't seem to be linked. Make sure: \n\n` + Platform.select({ ios: "- You have run 'pod install'\n", default: "" }) + "- You rebuilt the app after installing the package\n" + "- You are not using Expo Go\n"

// Try to get Turbo Module first (New Architecture)
let NativeTurboImagePicker: any = null

try {
  // @ts-ignore - TurboModuleRegistry might not be available
  NativeTurboImagePicker = TurboModuleRegistry?.get?.("RNTurboImagePicker")
} catch (e) {
  // Turbo Module not available
}

let _defaultThemeColor = "#10b981";
let _defaultLanguageCode = "en";

export interface InitOptions {
  languageCode?: string;
  themeColor?: string;
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
  init(licenseKey: string, options?: InitOptions): Promise<boolean>
  openGallery(options?: GalleryOptions): Promise<ImageResult[]>
  openEditor(options: EditorOptions): Promise<ImageResult>
  openViewer(options: ViewerOptions): Promise<void>
  updateSourceRect(rect: import("./types").SourceRect): Promise<void>
  closeGallery(): Promise<boolean>
  addSelectionChangeListener(listener: (event: SelectionChangeEvent) => void): () => void
  getDefaultAnimationConfig(): Promise<{ galleryOpen: number, galleryClose: number, editorOpen: number, editorClose: number, viewerOpen: number, viewerClose: number }>
  injectImageCache(urlString: string, localPath: string): Promise<boolean>
}

const TurboImagePicker: RNTurboImagePicker = {
  init: async (licenseKey: string, options?: InitOptions): Promise<boolean> => {
    if (options?.themeColor) {
      _defaultThemeColor = options.themeColor;
    }
    if (options?.languageCode) {
      _defaultLanguageCode = options.languageCode;
    }
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNTurboImagePickerModule.init(licenseKey)
  },

  openGallery: async (options: GalleryOptions = {}): Promise<ImageResult[]> => {
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }

    // 콜백 이벤트 임시 리스너 등록
    let subscriptionSelChange: any = null
    let subscriptionImgProcessed: any = null
    
    if (options.onSelectionChange) {
      subscriptionSelChange = eventEmitter.addListener("onSelectionChange", options.onSelectionChange)
    }
    if (options.onImageProcessed) {
      subscriptionImgProcessed = eventEmitter.addListener("onImageProcessed", options.onImageProcessed)
    }

    try {
      // 이벤트 콜백은 네이티브로 전달하지 않음
      const { onSelectionChange, onImageProcessed, ...restOptions } = options
      const nativeOptions = {
        themeColor: _defaultThemeColor,
        languageCode: _defaultLanguageCode,
        ...restOptions,
      }
      const result = await RNTurboImagePickerModule.openGallery(nativeOptions)
      return result
    } finally {
      // 갤러리가 닫히면 onSelectionChange 리스너 제거
      if (subscriptionSelChange) {
        subscriptionSelChange.remove()
      }
      // asyncProcessing 모드가 아닐 때만 onImageProcessed 리스너 제거 (async 모드에선 백그라운드 처리를 위해 유지해야 함)
      // 호출부에서 수동으로 제거하거나, 최종 완료 시 정리하는 구조가 필요할 수 있음
      if (!options.asyncProcessing && subscriptionImgProcessed) {
        subscriptionImgProcessed.remove()
      }
    }
  },

  openEditor: async (options: EditorOptions): Promise<ImageResult> => {
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }
    const mergedOptions = {
      themeColor: _defaultThemeColor,
      languageCode: _defaultLanguageCode,
      ...options,
    }
    return RNTurboImagePickerModule.openEditor(mergedOptions)
  },

  openViewer: async (options: ViewerOptions): Promise<void> => {
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }

    let subscriptionPageSelected: any = null
    if (options.onPageSelected) {
      subscriptionPageSelected = eventEmitter.addListener("onPageSelected", (event: any) => {
        if (options.onPageSelected && event && typeof event.index === 'number') {
          options.onPageSelected(event.index)
        }
      })
    }

    let subscriptionViewerOpened: any = null
    // iOS 네이티브 쪽에는 "onViewerOpened" 이벤트가 구현되어 있지 않습니다(Android 전용 —
    // 오버레이 뷰어의 열기 애니메이션 완료 시점을 알려주는 이벤트). iOS에서 무조건 구독을
    // 시도하면 RCTEventEmitter가 "onViewerOpened is not a supported event type" 경고를 던지므로,
    // Android에서만 등록합니다.
    if (options.onViewerOpened && Platform.OS === "android") {
      subscriptionViewerOpened = eventEmitter.addListener("onViewerOpened", () => {
        try {
          if (options.onViewerOpened) {
            options.onViewerOpened()
          }
        } catch (e) {
          console.error("[RNTurboImagePicker] options.onViewerOpened() threw:", e)
        }
        if (subscriptionViewerOpened) {
          subscriptionViewerOpened.remove()
        }
      })
    }

    let subscriptionViewerWillClose: any = null
    let deviceSubscriptionViewerWillClose: any = null

    if (options.onViewerWillClose) {
      const closeHandler = () => {
        if (options.onViewerWillClose) {
          options.onViewerWillClose()
        }
        if (subscriptionPageSelected) {
          subscriptionPageSelected.remove()
        }
        if (subscriptionViewerOpened) {
          subscriptionViewerOpened.remove()
        }
        if (subscriptionViewerWillClose) {
          subscriptionViewerWillClose.remove()
        }
        if (deviceSubscriptionViewerWillClose) {
          deviceSubscriptionViewerWillClose.remove()
        }
      };

      subscriptionViewerWillClose = eventEmitter.addListener("onViewerWillClose", closeHandler);

      if (Platform.OS === "android") {
        const { DeviceEventEmitter } = require("react-native");
        deviceSubscriptionViewerWillClose = DeviceEventEmitter.addListener("onViewerWillClose", closeHandler);
      }
    }

    try {
      const { onPageSelected, onViewerWillClose, onViewerOpened, ...restOptions } = options
      const mergedOptions = {
        themeColor: _defaultThemeColor,
        languageCode: _defaultLanguageCode,
        ...restOptions,
      }
      return await RNTurboImagePickerModule.openViewer(mergedOptions)
    } finally {
      // Listeners are now removed inside the onViewerWillClose callback
    }
  },

  updateSourceRect: async (rect: import("./types").SourceRect): Promise<void> => {
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNTurboImagePickerModule.updateSourceRect(rect)
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

  getDefaultAnimationConfig: async (): Promise<{ galleryOpen: number, galleryClose: number, editorOpen: number, editorClose: number, viewerOpen: number, viewerClose: number }> => {
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }
    return RNTurboImagePickerModule.getDefaultAnimationConfig()
  },

  injectImageCache: async (urlString: string, localPath: string): Promise<boolean> => {
    if (!RNTurboImagePickerModule) {
      throw new Error(LINKING_ERROR)
    }
    if (RNTurboImagePickerModule.injectImageCache) {
      return RNTurboImagePickerModule.injectImageCache(urlString, localPath)
    }
    return false;
  },
}

// Export info about which architecture is being used
export const isUsingTurboModule = !!NativeTurboImagePicker
export const isUsingLegacyModule = !!LegacyModule && !NativeTurboImagePicker

export default TurboImagePicker
