<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\AchievementLogic;

/**
 * アチーブメント関連のHTTPリクエストを処理するコントローラー。
 */
final class AchievementController
{
    public function __construct(private AchievementLogic $achievementLogic)
    {
    }

    /**
     * アチーブメントに関する操作結果を返す。
     */
    public function execute(int $userId, int $achievementId): array
    {
        $succeeded = $this->achievementLogic->process($userId, $achievementId);

        return ['succeeded' => $succeeded];
    }

    public function summary(int $userId): array
    {
        return $this->achievementLogic->buildSummary($userId);
    }
}
