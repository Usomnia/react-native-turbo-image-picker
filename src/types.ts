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
  openDuration?: number
  closeDuration?: number
}

export interface ViewerOptions {
  images: string[]
  placeholderImages?: string[]
  initialIndex?: number
  themeColor?: string // Added themeColor for Android
  title?: string
  animationType?: 'slide' | 'fade' | 'zoom'
  closeAnimationType?: 'slide' | 'fade' | 'zoom'
  sourceRect?: SourceRect
  sourceBorderRadius?: number
  sourceBackgroundColor?: string
  sourceBorderCorners?: ('topLeft' | 'topRight' | 'bottomLeft' | 'bottomRight')[]
  hideSourceImage?: boolean
  onPageSelected?: (index: number) => void
  onViewerWillClose?: () => void
  /**
   * Android only. 열기 애니메이션이 완전히 끝난 시점에 한 번 호출됩니다.
   * 배경(호스트 화면) 스크롤 보정을 이 콜백 안에서 실행하면, 애니메이션 도중에 보정이
   * 끼어들어 보이지 않고 뷰어가 화면을 완전히 가린 상태에서 안전하게 적용할 수 있습니다.
   */
  onViewerOpened?: () => void
  openDuration?: number
  closeDuration?: number
  /**
   * Android only. When true, opens the viewer as a full-screen DialogFragment
   * instead of a separate Activity. Avoids RN host Activity pausing (onPause),
   * which otherwise makes AppState briefly report background and the underlying
   * RN UI temporarily uncontrollable while the viewer is open.
   *
   * Known limitation: the DialogFragment is still a separate Android Window on
   * top of the host Activity's Window. While it's fully shown, the host Window
   * can be treated as not-visible by the system and its own render traversals
   * (layout/draw) can be skipped, so background RN view changes (e.g. list
   * scroll correction) may not actually take effect on screen until the
   * DialogFragment closes. See useOverlayViewer for a fix.
   * Default: false (existing Activity-based viewer).
   */
  useDialogViewer?: boolean
  /**
   * Android only. When true, opens the viewer as a View added directly on top
   * of the host Activity's existing Window (no separate Activity or Dialog
   * Window at all). This fixes the DialogFragment limitation above: since
   * there's only one Window, background RN view changes made while the viewer
   * is open are reflected immediately (same render tree, same frame).
   * Also avoids any window-focus-change AppState blips entirely.
   * Trade-off: back-press handling, touch blocking, and system-bar insets are
   * managed manually rather than via Activity/DialogFragment lifecycle, so
   * this needs extra QA (rotation, back gesture, other overlays like keyboard).
   * If both useDialogViewer and useOverlayViewer are true, useOverlayViewer wins.
   * Default: false.
   */
  useOverlayViewer?: boolean
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
  openDuration?: number
  closeDuration?: number
}

export interface RNTurboImagePicker {
  init(licenseKey: string): Promise<boolean>
  openGallery(options?: GalleryOptions): Promise<ImageResult[]>
  openEditor(options: EditorOptions): Promise<ImageResult>
  openViewer(options: ViewerOptions): Promise<void>
  updateViewerSourceRect(rect: SourceRect): Promise<void>
  closeGallery(): Promise<boolean>
  addSelectionChangeListener(listener: (event: SelectionChangeEvent) => void): () => void
  getDefaultAnimationConfig(): Promise<{ galleryOpen: number, galleryClose: number, editorOpen: number, editorClose: number, viewerOpen: number, viewerClose: number }>
}
