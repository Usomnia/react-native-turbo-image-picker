//
//  Logger.swift
//  ImageGalleryTest
//
//  Debug 빌드에서만 로그를 출력하는 Logger 래퍼
//  Release 빌드에서는 컴파일되지 않아 성능 최적화
//
//  사용법:
//  debugPrint("메시지") - Debug 빌드에서만 출력
//  print("메시지")      - 항상 출력 (에러용)
//

import Foundation

/// Debug 빌드에서만 print 실행
/// Release 빌드에서는 아무것도 하지 않음
func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    Swift.print(output, terminator: terminator)
    #endif
}

/// 전역 print 함수 덮어쓰기 (배포 시 모든 일반 print 로그 방지)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    Swift.print(output, terminator: terminator)
    #endif
}
