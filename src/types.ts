export interface ImageResult {
  originalUri: string // 원본 URI (ph:// 또는 file://)
  originalFileUri?: string // 원본 해상도의 파일 URI (file://) - 선택적
  originalWidth: number // 원본 width
  originalHeight: number // 원본 height
  uri?: string // resize된 이미지 URI (file://) - 선택적
  width?: number // resize된 width
  height?: number // resize된 height
  type: string // mime type
  caption?: string // 편집기에서 입력한 캡션
  fileName?: string // 파일명
  fileExtension?: string // 확장자
  fileSize?: number // 파일 크기 (bytes)
}

export interface SourceRect {
  x: number
  y: number
  width: number
  height: number
}

export interface GalleryOptions {
  maxSelection?: number
  maxWidth?: number // 최대 width
  maxHeight?: number // 최대 height
  mediaType?: "photo" | "video" | "all"
  quality?: number
  allItemsText?: string
  selectedItemsText?: string
  doneButtonText?: string
  recentsAlbumText?: string
  languageCode?: "da" | "de" | "en" | "es" | "fr" | "hi" | "id" | "it" | "ja" | "ko" | "ms" | "nl" | "pl" | "pt" | "ru" | "th" | "tr" | "vi" | "zh"
  autoCloseOnSelect?: boolean
  enableEditor?: boolean // 단일 이미지 선택 시 편집기 활성화 여부
  profileMode?: boolean // 1:1 프로필 크롭 모드 활성화 여부
  themeColor?: string // 테마 컬러 지정 (ex: "#FFEB3B")
  asyncProcessing?: boolean // 완전 비동기 이벤트 리턴 여부
  onSelectionChange?: (event: SelectionChangeEvent) => void
  onImageProcessed?: (event: any) => void
}

export interface ViewerOptions {
  images: string[]
  initialIndex?: number
  themeColor?: string // Added themeColor for Android
  title?: string
  animationType?: 'slide' | 'fade' | 'zoom'
  closeAnimationType?: 'slide' | 'fade' | 'zoom'
  sourceRect?: SourceRect
  onPageSelected?: (index: number) => void
}

export interface SelectionChangeEvent {
  selectedCount: number
  maxSelection: number
}

export interface EditorOptions {
  uri: string // 편집할 이미지의 uri (originalUri)
  editedFileUri?: string // 이전에 편집한 이미지의 파일 경로
  themeColor?: string // 편집기 테마 컬러
  maxWidth?: number // 최대 width
  maxHeight?: number // 최대 height
}

export interface RNTurboImagePicker {
  init(licenseKey: string): Promise<boolean>
  openGallery(options?: GalleryOptions): Promise<ImageResult[]>
  openEditor(options: EditorOptions): Promise<ImageResult>
  openViewer(options: ViewerOptions): Promise<void>
  updateViewerSourceRect(rect: SourceRect): Promise<void>
  closeGallery(): Promise<boolean>
  addSelectionChangeListener(listener: (event: SelectionChangeEvent) => void): () => void
}
