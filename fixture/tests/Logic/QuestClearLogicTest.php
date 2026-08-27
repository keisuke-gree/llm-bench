<?php

declare(strict_types=1);

namespace Bench\Tests\Logic;

use Bench\Dao\QuestDao;
use Bench\Logic\QuestClearLogic;
use Bench\Logic\RewardCalculator;
use Bench\Model\UserContext;
use PHPUnit\Framework\TestCase;

/**
 * QuestClearLogic::clear() の報酬計算に関するテスト。
 */
final class QuestClearLogicTest extends TestCase
{
    private QuestDao $questDao;

    protected function setUp(): void
    {
        parent::setUp();
        $this->questDao = $this->createMock(QuestDao::class);
        $this->questDao->method('findById')->willReturn([
            'rank' => 1,
            'clearCount' => 0,
        ]);
    }

    public function testClearWithoutCampaignReturnsBaseAmount(): void
    {
        $logic = new QuestClearLogic($this->questDao, new RewardCalculator());
        $context = new UserContext(
            userId: 1001,
            level: 10,
            campaignId: null,
        );
        $now = new \DateTimeImmutable('2026-08-05 12:00:00');
        $amount = $logic->clear(1, $context, $now);

        self::assertSame(100, $amount);
    }

    public function testClearDuringCampaignMidPeriodAppliesBonus(): void
    {
        $logic = new QuestClearLogic($this->questDao, new RewardCalculator());
        $context = new UserContext(
            userId: 1002,
            level: 15,
            campaignId: 1,
            campaignStartAt: new \DateTimeImmutable('2026-08-01 00:00:00'),
            campaignEndAt: new \DateTimeImmutable('2026-08-10 23:59:59'),
        );
        $now = new \DateTimeImmutable('2026-08-05 12:00:00');
        $amount = $logic->clear(1, $context, $now);

        self::assertSame(150, $amount);
    }


    /**
     * キャンペーン最終日（開催終了時刻ちょうど）にクエストをクリアした場合も、
     * その日のうちはボーナスレートが適用され続ける想定である。
     */
    public function testBonusAppliedOnCampaignLastDay(): void
    {
        $logic = new QuestClearLogic($this->questDao, new RewardCalculator());
        $context = new UserContext(
            userId: 1003,
            level: 18,
            campaignId: 1,
            campaignStartAt: new \DateTimeImmutable('2026-08-01 00:00:00'),
            campaignEndAt: new \DateTimeImmutable('2026-08-10 23:59:59'),
        );
        $now = new \DateTimeImmutable('2026-08-10 23:59:59');
        $amount = $logic->clear(1, $context, $now);

        self::assertEquals(150, $amount);
    }
}
