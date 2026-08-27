<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\TutorialDao;

/**
 * チュートリアル報酬に関する補助的な業務ロジックを担うクラス。
 */
final class TutorialRewardLogic
{
    public function __construct(private TutorialDao $tutorialDao)
    {
    }

    /**
     * チュートリアル完了段階に応じた報酬量を算出する。
     */
    public function resolveRewardAmount(int $stepNumber): int
    {
        $baseAmount = 30;

        return $baseAmount + $stepNumber * 10;
    }
}
