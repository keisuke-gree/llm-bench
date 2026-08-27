<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\TutorialLogic;

/**
 * チュートリアル関連のHTTPリクエストを処理するコントローラー。
 */
final class TutorialController
{
    public function __construct(private TutorialLogic $tutorialLogic)
    {
    }

    public function show(int $tutorialId): array
    {
        $result = $this->tutorialLogic->fetchDetail($tutorialId);

        return ['tutorial' => $result];
    }

    /**
     * チュートリアルの一覧を取得して返す。
     */
    public function list(int $userId): array
    {
        $items = $this->tutorialLogic->listForUser($userId);

        return ['items' => $items, 'count' => count($items)];
    }
}
