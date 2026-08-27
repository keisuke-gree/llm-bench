<?php

declare(strict_types=1);

namespace Bench\Dao;

/**
 * 報酬関連データの永続化を担当するクラス。
 *
 * @see \Bench\Logic\RewardCalculator::applyBonusRate() ボーナスレート適用後の金額がここに保存される
 */
final class RewardDao
{
    /**
     * @param array<int, array{userId:int,amount:int}> $store
     */
    public function __construct(private array $store = [])
    {
    }

    public function save(int $userId, int $amount): void
    {
        $this->store[] = ['userId' => $userId, 'amount' => $amount];
    }

    /**
     * @return array{userId:int,amount:int}|null
     */
    public function findLatestByUserId(int $userId): ?array
    {
        foreach (array_reverse($this->store) as $record) {
            if ($record['userId'] === $userId) {
                return $record;
            }
        }

        return null;
    }
}
