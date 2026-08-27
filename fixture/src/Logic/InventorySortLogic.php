<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\InventoryDao;

/**
 * 所持品整列に関する補助的な業務ロジックを担うクラス。
 */
final class InventorySortLogic
{
    public function __construct(private InventoryDao $inventoryDao)
    {
    }

    /**
     * @param list<array<string,mixed>> $items
     * @return list<array<string,mixed>>
     */
    public function sortByAcquiredOrder(array $items): array
    {
        usort($items, static fn (array $a, array $b): int => ($a['id'] ?? 0) <=> ($b['id'] ?? 0));

        return $items;
    }
}
