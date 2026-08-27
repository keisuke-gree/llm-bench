<?php

declare(strict_types=1);

namespace Bench\Logic;

use Bench\Dao\MailDao;

/**
 * お知らせメールに関する業務ロジックを担うクラス。
 */
final class MailLogic
{
    public function __construct(private MailDao $mailDao)
    {
    }

    /**
     * @return array<string,mixed>
     */
    public function fetchDetail(int $mailId): array
    {
        return $this->mailDao->findById($mailId);
    }

    /**
     * @return list<array<string,mixed>>
     */
    public function listForUser(int $userId): array
    {
        $records = $this->mailDao->findAllByUserId($userId);

        usort($records, static fn (array $a, array $b): int => ($a['sortOrder'] ?? 0) <=> ($b['sortOrder'] ?? 0));

        return $records;
    }

    public function process(int $userId, int $mailId): bool
    {
        if ($mailId <= 0) {
            return false;
        }

        $this->mailDao->markProcessed($userId, $mailId);

        return true;
    }

    /**
     * ユーザー向けのお知らせメールサマリーを組み立てる。
     */
    public function buildSummary(int $userId): array
    {
        $records = $this->mailDao->findAllByUserId($userId);

        return ['userId' => $userId, 'total' => count($records)];
    }
}
