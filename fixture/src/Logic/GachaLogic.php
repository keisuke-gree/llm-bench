<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\GachaDao;

/**
 * ガチャに関する業務ロジックを担うクラス。
 */
final class GachaLogic
{
    public function __construct(private GachaDao $gachaDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $gachaId): array
    {
        $record = $this->gachaDao->findById($gachaId);

        return $record === [] ? ['found' => false] : $record;
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        return array_map(
            static fn (array $record): array => $record + ['userId' => $userId],
            $this->gachaDao->findAllByUserId($userId),
        );
    }

    public function process(int $userId, int $gachaId): bool
    {
        return match (true) {
            $gachaId <= 0 => false,
            default => $this->gachaDao->markProcessed($userId, $gachaId) || true,
        };
    }

    /**
     * ユーザー向けのガチャサマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->gachaDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
