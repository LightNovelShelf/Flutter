/// 图床按尺寸取图的客户端约定。
///
/// 图床支持用 `height` 查询参数要一张缩放过的图，但只接受 256 的整倍数，其它值一律
/// 无效并原样返回未缩放的图。档位高于图片自身高度时同样不生效。
///
/// 步进的意义是把同一张图的变体收敛成有限几档，客户端必须先量化再请求，直接把像素
/// 高度塞进地址会让缓存彻底散掉。
library;

/// 图床认可的高度步进。
const int imageHeightStep = 256;

/// 请求上限。再往上基本都超过图片自身高度、拿不到缩放版本，只会多出无用的档位。
const int maxImageHeightRequest = 4096;

/// 把逻辑高度按 DPR 折成物理像素，再就近取档。
///
/// 客户端不再用 `memCacheHeight` 二次限制解码，所以这个档位是尺寸的唯一控制点 ——
/// 它同时决定下载的字节数和解码后位图占的内存。
///
/// 就近而不是向上取整：站内封面本身就不算大，向上取整很容易整档跨过图片自身高度，
/// 那样缩放不生效、白白拿回整张原图。就近取档最坏让图比显示区矮半档，`BoxFit` 补上
/// 3~4% 的放大，肉眼无感。
int imageHeightBucketFor(double logicalHeight, double devicePixelRatio) {
  final double physical = logicalHeight * devicePixelRatio;
  if (!physical.isFinite || physical <= 0) return imageHeightStep;
  final int bucket = (physical / imageHeightStep).round() * imageHeightStep;
  return bucket.clamp(imageHeightStep, maxImageHeightRequest);
}

/// 写入 `height` 查询参数，保留地址上已有的其它参数。
///
/// 已存在 `height` 时就地替换，避免同一张图裂成两个缓存键。
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

/// 按显示尺寸取档并写进地址。展示与预取必须共用它，否则缓存键分叉、预取字节作废。
String sizedImageUrl(
  String url, {
  required double logicalHeight,
  required double devicePixelRatio,
}) => withImageHeight(
  url,
  imageHeightBucketFor(logicalHeight, devicePixelRatio),
);
