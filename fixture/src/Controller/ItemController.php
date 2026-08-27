<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\ItemLogic;

/**
 * アイテム関連のHTTPリクエストを処理するコントローラー。
 */
final class ItemController
{
    public function __construct(private ItemLogic $itemLogic)
    {
    }

    public function show(int $itemId): array
    {
        $result = $this->itemLogic->fetchDetail($itemId);

        return ['item' => $result];
    }

    /**
     * アイテムの一覧を取得して返す。
     */
    public function list(int $userId): array
    {
        $items = $this->itemLogic->listForUser($userId);

        return ['items' => $items, 'count' => count($items)];
    }
}
