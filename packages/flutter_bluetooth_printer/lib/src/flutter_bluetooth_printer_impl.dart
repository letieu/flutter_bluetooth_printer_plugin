part of flutter_bluetooth_printer;

class DiscoveryResult extends DiscoveryState {
  final List<BluetoothDevice> devices;
  DiscoveryResult({required this.devices});
}

class FlutterBluetoothPrinter {
  static void registerWith() {
    FlutterBluetoothPrinterPlatform.instance = _MethodChannelBluetoothPrinter();
  }

  static Stream<DiscoveryState> _discovery() async* {
    final result = <BluetoothDevice>[];
    await for (final state
        in FlutterBluetoothPrinterPlatform.instance.discovery) {
      if (state is BluetoothDevice) {
        result.add(state);
        yield DiscoveryResult(devices: result.toSet().toList());
      } else {
        result.clear();
        yield state;
      }
    }
  }

  static ValueNotifier<BluetoothConnectionState> get connectionStateNotifier =>
      FlutterBluetoothPrinterPlatform.instance.connectionStateNotifier;

  static Stream<DiscoveryState> get discovery => _discovery();

  static Future<void> printBytes({
    required String address,
    required Uint8List data,

    /// if true, you should manually disconnect the printer after finished
    required bool keepConnected,
    ProgressCallback? onProgress,
  }) async {
    await FlutterBluetoothPrinterPlatform.instance.write(
      address: address,
      data: data,
      onProgress: onProgress,
      keepConnected: keepConnected,
    );
  }

  static Future<void> printImage({
    required String address,
    required List<int> imageBytes,
    required int imageWidth,
    required int imageHeight,
    PaperSize paperSize = PaperSize.mm58,
    ProgressCallback? onProgress,
    int addFeeds = 0,
    bool useImageRaster = false,
    required bool keepConnected,
  }) async {
    final bytes = await _optimizeImage(
      paperSize: paperSize,
      src: imageBytes,
      srcWidth: imageWidth,
      srcHeight: imageHeight,
    );

    Uint8List data = Uint8List.fromList(bytes);
    img.Image src = img.decodeJpg(data) as img.Image;

    final profile = await CapabilityProfile.load();
    final generator = Generator(
      paperSize,
      profile,
      spaceBetweenRows: 0,
    );
    List<int> imageData;
    if (useImageRaster) {
      imageData = generator.imageRaster(
        src,
        highDensityHorizontal: true,
        highDensityVertical: true,
        imageFn: PosImageFn.bitImageRaster,
      );
    } else {
      imageData = generator.image(src);
    }

    final additional = [
      ...generator.emptyLines(addFeeds),
      ...generator.text('.'),
    ];

    return printBytes(
      keepConnected: keepConnected,
      address: address,
      data: Uint8List.fromList([
        ...generator.reset(),
        ...imageData,
        ...generator.reset(),
        ...additional,
      ]),
      onProgress: onProgress,
    );
  }

  static Future<List<int>> _optimizeImage({
    required List<int> src,
    required PaperSize paperSize,
    required int srcWidth,
    required int srcHeight,
  }) async {
    final arg = <String, dynamic>{
      'src': src,
      'width': srcWidth,
      'height': srcHeight,
      'paperSize': paperSize,
    };

    if (kIsWeb) {
      return _blackwhiteInternal(arg);
    }

    return compute(_blackwhiteInternal, arg);
  }

  static Future<List<int>> _blackwhiteInternal(Map<String, dynamic> arg) async {
    final srcBytes = arg['src'] as List<int>;
    final width = arg['width'] as int;
    final height = arg['height'] as int;
    final paperSize = arg['paperSize'] as PaperSize;

    final ByteBuffer bytes = Uint8List.fromList(srcBytes).buffer;
    img.Image src =
        img.Image.fromBytes(width: width, height: height, bytes: bytes);
    final w = src.width;
    final h = src.height;

    src = img.smooth(src, weight: 1.5);
    final res = img.Image(width: w, height: h);
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        // TODO: convert to black and white
      }
    }

    src = res;
    src = img.pixelate(
      src,
      size: (src.width / paperSize.width).round(),
      mode: img.PixelateMode.average,
    );

    final dotsPerLine = paperSize.width;
    // make sure image not bigger than printable area
    if (src.width > dotsPerLine) {
      double ratio = dotsPerLine / src.width;
      int height = (src.height * ratio).ceil();
      src = img.copyResize(
        src,
        width: dotsPerLine,
        height: height,
      );
    }

    return img.encodeJpg(src);
  }

  static Future<BluetoothDevice?> selectDevice(BuildContext context) async {
    final selected = await showModalBottomSheet(
      context: context,
      builder: (context) => const BluetoothDeviceSelector(),
    );
    if (selected is BluetoothDevice) {
      return selected;
    }
    return null;
  }

  static Future<bool> disconnect(String address) async {
    return FlutterBluetoothPrinterPlatform.instance.disconnect(address);
  }
}
