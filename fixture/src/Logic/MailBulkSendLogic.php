<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\MailDao;

/**
 * お知らせメール一括送信に関する補助的な業務ロジックを担うクラス。
 */
final class MailBulkSendLogic
{
    public function __construct(private MailDao $mailDao)
    {
    }

    /**
     * @param list<int> $userIds
     */
    public function sendToUsers(int $mailId, array $userIds): int
    {
        $record = $this->mailDao->findById($mailId);
        if ($record === []) {
            return 0;
        }

        $sent = 0;
        foreach ($userIds as $userId) {
            $this->mailDao->markProcessed($userId, $mailId);
            $sent++;
        }

        return $sent;
    }
}
