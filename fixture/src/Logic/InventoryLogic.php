<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\InventoryDao;

/**
 * 所持品に関する業務ロジックを担うクラス。
 */
final class InventoryLogic
{
    public function __construct(private InventoryDao $inventoryDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $inventoryId): array
    {
        return $this->inventoryDao->findById($inventoryId);
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        $records = $this->inventoryDao->findAllByUserId($userId);
        $result = [];

        foreach ($records as $record) {
            if ($record['active'] ?? true) {
                $result[] = $record;
            }
        }

        return $result;
    }

    public function process(int $userId, int $inventoryId): bool
    {
        $record = $this->inventoryDao->findById($inventoryId);
        if ($record === []) {
            return false;
        }

        $this->inventoryDao->markProcessed($userId, $inventoryId);

        return true;
    }

    /**
     * ユーザー向けの所持品サマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->inventoryDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
