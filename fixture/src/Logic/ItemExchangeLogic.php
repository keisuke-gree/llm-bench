<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\ItemDao;

/**
 * アイテム交換に関する補助的な業務ロジックを担うクラス。
 */
final class ItemExchangeLogic
{
    public function __construct(private ItemDao $itemDao)
    {
    }

    /**
     * 複数アイテムをまとめて交換する。
     *
     * @param list<int> $itemIds
     * @return list<array<string,mixed>>
     */
    public function exchangeBulk(int $userId, array $itemIds): array
    {
        $results = [];

        foreach ($itemIds as $itemId) {
            $record = $this->itemDao->findById($itemId);
            if ($record === []) {
                continue;
            }

            $this->itemDao->markProcessed($userId, $itemId);
            $results[] = $record;
        }

        return $results;
    }
}
