<?php

declare(strict_types=1);

namespace Bench\Model;

use Bench\Logic\RewardCalculator;

/**
 * ユーザーへの報酬付与結果を表すモデル。
 */
final class UserRewardModel
{
    private int $confirmedAmount = 0;

    public function __construct(
        public readonly int $userId,
        public readonly int $baseAmount,
    ) {
    }

    /**
     * キャンペーン状況を反映した確定報酬額を計算して保持する。
     */
    public function confirm(UserContext $context, \DateTimeImmutable $now): int
    {
        $calculator = new RewardCalculator();

        $this->confirmedAmount = $calculator->applyBonusRate($this->baseAmount, $context, $now);

        return $this->confirmedAmount;
    }

    public function getConfirmedAmount(): int
    {
        return $this->confirmedAmount;
    }
}
