module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.rnturboimagepicker.RNTurboImagePickerPackage;',
        packageInstance: 'new RNTurboImagePickerPackage()',
      },
      ios: {},
    },
  },
};
