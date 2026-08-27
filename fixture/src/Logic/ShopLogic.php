<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\ShopDao;

/**
 * ショップに関する業務ロジックを担うクラス。
 */
final class ShopLogic
{
    public function __construct(private ShopDao $shopDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $shopId): array
    {
        $record = $this->shopDao->findById($shopId);

        return $record === [] ? ['found' => false] : $record;
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        return array_map(
            static fn (array $record): array => $record + ['userId' => $userId],
            $this->shopDao->findAllByUserId($userId),
        );
    }

    public function process(int $userId, int $shopId): bool
    {
        return match (true) {
            $shopId <= 0 => false,
            default => $this->shopDao->markProcessed($userId, $shopId) || true,
        };
    }

    /**
     * ユーザー向けのショップサマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->shopDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
