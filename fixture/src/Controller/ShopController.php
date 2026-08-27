<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\ShopLogic;

/**
 * ショップ関連のHTTPリクエストを処理するコントローラー。
 */
final class ShopController
{
    public function __construct(private ShopLogic $shopLogic)
    {
    }

    public function show(int $shopId): array
    {
        $result = $this->shopLogic->fetchDetail($shopId);

        return ['shop' => $result];
    }

    /**
     * ショップの一覧を取得して返す。
     */
    public function list(int $userId): array
    {
        $items = $this->shopLogic->listForUser($userId);

        return ['items' => $items, 'count' => count($items)];
    }
}
