export interface ImageResult {
  uri: string
  width: number
  height: number
  type: string
}

export interface GalleryOptions {
  maxSelection?: number
  mediaType?: "photo" | "video" | "all"
  quality?: number
  allItemsText?: string
  selectedItemsText?: string
  doneButtonText?: string
  recentsAlbumText?: string
  languageCode?: "da" | "de" | "en" | "es" | "fr" | "hi" | "id" | "it" | "ja" | "ko" | "ms" | "nl" | "pl" | "pt" | "ru" | "th" | "tr" | "vi" | "zh"
  autoCloseOnSelect?: boolean
  enableEditor?: boolean // 단일 이미지 선택 시 편집기 활성화 여부
  themeColor?: string // 테마 컬러 지정 (ex: "#FFEB3B")
  onSelectionChange?: (event: SelectionChangeEvent) => void
}

export interface SelectionChangeEvent {
  selectedCount: number
  maxSelection: number
}

export interface RNTurboImagePicker {
  openGallery(options?: GalleryOptions): Promise<ImageResult[]>
  closeGallery(): Promise<boolean>
  addSelectionChangeListener(listener: (event: SelectionChangeEvent) => void): () => void
}

/**
 * Returns true if using Turbo Module (New Architecture)
 */
export const isUsingTurboModule: boolean

/**
 * Returns true if using Legacy Native Module (Old Architecture)
 */
export const isUsingLegacyModule: boolean

declare const TurboImagePicker: RNTurboImagePicker

export default TurboImagePicker
