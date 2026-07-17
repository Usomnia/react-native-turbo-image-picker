import type { TurboModule } from "react-native"
import { TurboModuleRegistry } from "react-native"

export interface Spec extends TurboModule {
  init(licenseKey: string): Promise<boolean>;
  openGallery(options: Object): Promise<Object[]>;
  openEditor(options: Object): Promise<Object>;
  openViewer(options: Object): Promise<void>;
  closeGallery(): Promise<boolean>;
  
  // RCTEventEmitter 필수 규격 (Turbo Module에서 이벤트 방출 시 필수)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>("RNTurboImagePicker");
