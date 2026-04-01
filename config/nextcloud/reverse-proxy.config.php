<?php

$publicHost = getenv('PUBLIC_APP_HOST') ?: '';
$publicScheme = getenv('PUBLIC_APP_SCHEME') ?: 'https';
$publicPath = getenv('NEXTCLOUD_PUBLIC_PATH') ?: '/nextcloud';
$trustedProxyList = getenv('NEXTCLOUD_TRUSTED_PROXIES') ?: '127.0.0.1 172.16.0.0/12';
$trustedProxies = array_values(array_filter(preg_split('/\s+/', trim($trustedProxyList))));

if (!isset($CONFIG) || !is_array($CONFIG)) {
    $CONFIG = [];
}

if ($publicHost !== '') {
    $CONFIG['overwritehost'] = $publicHost;
    $CONFIG['overwriteprotocol'] = $publicScheme;
    $CONFIG['overwritewebroot'] = $publicPath;
    $CONFIG['overwrite.cli.url'] = sprintf('%s://%s%s', $publicScheme, $publicHost, $publicPath);
}

if ($trustedProxies !== []) {
    $CONFIG['trusted_proxies'] = $trustedProxies;
}

