<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\ItemDao;

/**
 * アイテムに関する業務ロジックを担うクラス。
 */
final class ItemLogic
{
    public function __construct(private ItemDao $itemDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $itemId): array
    {
        return $this->itemDao->findById($itemId);
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        $records = $this->itemDao->findAllByUserId($userId);
        $result = [];

        foreach ($records as $record) {
            if ($record['active'] ?? true) {
                $result[] = $record;
            }
        }

        return $result;
    }

    public function process(int $userId, int $itemId): bool
    {
        $record = $this->itemDao->findById($itemId);
        if ($record === []) {
            return false;
        }

        $this->itemDao->markProcessed($userId, $itemId);

        return true;
    }

    /**
     * ユーザー向けのアイテムサマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->itemDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
