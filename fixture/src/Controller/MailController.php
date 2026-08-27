<?php

declare(strict_types=1);

namespace Bench\Controller;

use Bench\Logic\MailLogic;

/**
 * お知らせメール関連のHTTPリクエストを処理するコントローラー。
 */
final class MailController
{
    public function __construct(private MailLogic $mailLogic)
    {
    }

    /**
     * お知らせメールに関する操作結果を返す。
     */
    public function execute(int $userId, int $mailId): array
    {
        $succeeded = $this->mailLogic->process($userId, $mailId);

        return ['succeeded' => $succeeded];
    }

    public function summary(int $userId): array
    {
        return $this->mailLogic->buildSummary($userId);
    }
}
