<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\InventoryLogic;

/**
 * 所持品関連のHTTPリクエストを処理するコントローラー。
 */
final class InventoryController
{
    public function __construct(private InventoryLogic $inventoryLogic)
    {
    }

    /**
     * 所持品に関する操作結果を返す。
     */
    public function execute(int $userId, int $inventoryId): array
    {
        $succeeded = $this->inventoryLogic->process($userId, $inventoryId);

        return ['succeeded' => $succeeded];
    }

    public function summary(int $userId): array
    {
        return $this->inventoryLogic->buildSummary($userId);
    }
}
