/// 图床按尺寸取图的客户端约定。
///
/// `height` 查询参数只接受 256 的整倍数，其它值无效并返回未缩放的图，档位高于
/// 图片自身高度时同样不生效。请求前必须先量化，否则缓存键分散。
library;

/// 图床认可的高度步进。
const int imageHeightStep = 256;

/// 请求上限，再往上通常超过图片自身高度、拿不到缩放版本。
const int maxImageHeightRequest = 4096;

/// 把逻辑高度按 DPR 折成物理像素，再就近取档。
///
/// 档位是尺寸的唯一控制点，同时决定下载的字节数和解码后位图占的内存。
///
/// 取就近档而不是向上取整，否则容易跨过图片自身高度导致缩放不生效；代价是最坏
/// 比显示区矮半档，由 `BoxFit` 放大补足。
int imageHeightBucketFor(double logicalHeight, double devicePixelRatio) {
  final double physical = logicalHeight * devicePixelRatio;
  if (!physical.isFinite || physical <= 0) return imageHeightStep;
  final int bucket = (physical / imageHeightStep).round() * imageHeightStep;
  return bucket.clamp(imageHeightStep, maxImageHeightRequest);
}

/// 写入 `height` 查询参数，保留地址上已有的其它参数。
///
/// 已存在 `height` 时就地替换，避免同一张图产生两个缓存键。
String withImageHeight(String url, int height) {
  if (url.isEmpty || height <= 0) return url;
  final int queryStart = url.indexOf('?');
  if (queryStart < 0) return '$url?height=$height';
  if (queryStart == url.length - 1) return '$url' 'height=$height';

  var pairStart = queryStart + 1;
  while (pairStart < url.length) {
    final int nextAmp = url.indexOf('&', pairStart);
    final int pairEnd = nextAmp < 0 ? url.length : nextAmp;
    final int separator = url.indexOf('=', pairStart);
    if (separator >= pairStart &&
        separator < pairEnd &&
        url.substring(pairStart, separator) == 'height') {
      return url.substring(0, separator + 1) +
          height.toString() +
          url.substring(pairEnd);
    }
    if (nextAmp < 0) break;
    pairStart = pairEnd + 1;
  }
  return '$url&height=$height';
}

/// 按显示尺寸取档并写进地址，展示与预取必须共用，否则预取的缓存键对不上。
String sizedImageUrl(
  String url, {
  required double logicalHeight,
  required double devicePixelRatio,
}) => withImageHeight(
  url,
  imageHeightBucketFor(logicalHeight, devicePixelRatio),
);
