module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.rnturboimagepicker.RNTurboImagePickerPackage;',
        packageInstance: 'new RNTurboImagePickerPackage()',
        cmakeListsPath: 'build/generated/source/codegen/jni/CMakeLists.txt',
        libraryName: 'RNTurboImagePickerSpec',
      },
      ios: {},
    },
  },
};
