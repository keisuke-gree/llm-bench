<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\LoginBonusLogic;

/**
 * ログインボーナス関連のHTTPリクエストを処理するコントローラー。
 */
final class LoginBonusController
{
    public function __construct(private LoginBonusLogic $loginBonusLogic)
    {
    }

    public function show(int $loginBonusId): array
    {
        $result = $this->loginBonusLogic->fetchDetail($loginBonusId);

        return ['loginBonus' => $result];
    }

    /**
     * ログインボーナスの一覧を取得して返す。
     */
    public function list(int $userId): array
    {
        $items = $this->loginBonusLogic->listForUser($userId);

        return ['items' => $items, 'count' => count($items)];
    }
}
