<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\GachaLogic;

/**
 * ガチャ関連のHTTPリクエストを処理するコントローラー。
 */
final class GachaController
{
    public function __construct(private GachaLogic $gachaLogic)
    {
    }

    /**
     * ガチャに関する操作結果を返す。
     */
    public function execute(int $userId, int $gachaId): array
    {
        $succeeded = $this->gachaLogic->process($userId, $gachaId);

        return ['succeeded' => $succeeded];
    }

    public function summary(int $userId): array
    {
        return $this->gachaLogic->buildSummary($userId);
    }
}
