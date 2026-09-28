"""Generate reproducible history regression inputs from canonical data (no game data)."""
import importlib.util
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('translations', root / '_TranslationWorkspace/import_translations.py')
data = importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)
translations, _, _, _ = data.read_split_files()
mapping = {}
for line in (root / 'Client/BepInEx/config/RO3.LocalizationOverrides.tsv').read_text(encoding='utf-8-sig').splitlines():
    fields = line.split('\t', 2)
    if len(fields) == 3 and not line.startswith('#'):
        mapping[fields[0]] = fields[1:]

def render(template):
    return data.RUNTIME_TOKEN_RE.sub(lambda m: '' if m[0].startswith('^{') else str(11 * int((re.search(r'\d+', m[0]) or ['1'])[0])), template)

rows = []
for key in data.KNOWN_LOCALIZATION_PATCH_IDS:
    if key not in mapping:
        raise ValueError('Missing historical ID: ' + key)
    english, japanese = mapping[key]
    # ID-specific ambiguous strings must be checked by ID, not global text.
    if key in ('25368', '26015', '44013', '44026', '50047', '61041', '61065'):
        rows.append(('id:' + key, english, japanese))
    else:
        rows.append(('text:' + key, render(english), render(japanese)))

for category in ('OBSERVED_UI_ZH_ALIASES', 'OBSERVED_STALL_TITLE_ALIASES', 'OBSERVED_STALL_ITEM_ALIASES',
                 'OBSERVED_CALENDAR_ZH_ALIASES', 'OBSERVED_HATCHERY_ZH_ALIASES',
                 'OBSERVED_HATCHERY_QUALITY_ALIASES'):
    for i, (source, target) in enumerate(getattr(data, category).items()):
        rows.append((category + ':' + str(i), source, target))
for key, source, target in data.build_item_alias_rows(translations):
    if key in ('12390001302', '12390001307'):
        rows.append(('stall-item:' + key, source, target))
for key, source, target in data.build_skill_alias_rows(translations):
    if key in ('10110200020', '10110200023', '10110200043', '10110200045',
               '10110200057', '10110201060', '11770000028',
               '11770000030', '11770000031'):
        rows.append(('skill-alias:' + key, source, target))
for key, (source, target) in data.KNOWN_LOCALIZATION_ID_JAPANESE_OVERRIDES.items():
    rows.append(('id:' + key, source, target))
for i, source in enumerate((data.KNOWN_KAFRA_BATTLEFIELD_MANAGER, data.KNOWN_KAFRA_BATTLEFIELD_ODIN_BODY)):
    combined = data.KNOWN_KAFRA_BATTLEFIELD_MANAGER + r'\n' + data.KNOWN_KAFRA_BATTLEFIELD_ODIN_BODY
    target = translations[combined].split(r'\n')[i]
    rows.append(('split-kafra:' + str(i), render(source), render(target)))
rows.extend([
    ('screen-skill-level-cn', '技能队列Lv.1', 'スキルバーLv.1'),
    ('screen-skill-level-tw', '技能隊列 Lv.10', 'スキルバー Lv.10'),
    ('screen-skill-level-free-text', 'TestPlayer:技能队列Lv.1', 'TestPlayer:技能队列Lv.1'),
    ('screen-reward-heading-cn', '恭喜获得', translations['Congrats on Obtaining']),
    ('screen-reward-heading-tw', '恭喜獲得', translations['Congrats on Obtaining']),
    ('screen-reward-heading-rich', '<color=#ffce63>恭喜获得</color>', '<color=#ffce63>' + translations['Congrats on Obtaining'] + '</color>'),
    ('screen-reward-heading-free-text', 'TestPlayer:恭喜获得宝石', 'TestPlayer:恭喜获得宝石'),
    ('latest-trophy-level', 'Reach Wardrobe Fashion Rating Lv. 3', 'ワードローブのファッション評価をLv.3にする'),
    ('latest-trophy-level-varied', 'Reach Wardrobe Fashion Rating Lv. 12', 'ワードローブのファッション評価をLv.12にする'),
    ('latest-trophy-appearance', 'Appearance 1', '外見 1'),
    ('latest-trophy-appearance-unknown', '外观TestPlayer', '外观TestPlayer'),
    ('latest-trophy-appearance-suffix', '外观11人', '外观11人'),
    ('latest-live-echo-name', '珠泪螺壳', 'パールティアコンチ'),
    ('latest-live-echo-rating', 'Rating 3875', '評価 3875'),
    ('latest-live-buff-stack', 'Admonitory Song of Suffering: Low Drone x1', '苦難の諫歌：ローハム x1'),
    ('latest-live-buff-stack-rich', '<color=#cc762a>Admonitory Song of Suffering: Low Drone</color> x12', '<color=#cc762a>苦難の諫歌：ローハム</color> x12'),
    ('latest-live-buff-unknown', 'Unlisted Buff x1', 'Unlisted Buff x1'),
    ('latest-trophy-counter', 'Trophies Achieved: <#c27b47>1</color>/11', '達成トロフィー：<#c27b47>1</color>/11'),
    ('latest-trophy-counter-plain', 'Trophies Achieved: 2/15', '達成トロフィー：2/15'),
    ('latest-trophy-claim', '一键领取', '一括受取'),
    ('latest-trophy-claim-traditional', '一鍵領取', '一括受取'),
    ('latest-mail-storage-literal', '邮件存储上限：${1}/${2}', 'メール保存上限：${1}/${2}'),
    ('latest-mail-storage-expanded', '邮件存储上限：42/80', 'メール保存上限：42/80'),
    ('latest-mail-storage-rich', '信件儲存上限：<color=#FA983A>42</color>/80', 'メール保存上限：<color=#FA983A>42</color>/80'),
    ('latest-profile-rank', 'ランク:无', 'ランク:なし'),
    ('latest-profile-rank-english', 'Rank: None', 'ランク: なし'),
    ('latest-profile-rank-rich', 'ランク:<color=#7e7361>無</color>', 'ランク:<color=#7e7361>なし</color>'),
    ('latest-profile-unknown', 'ランク:无題', 'ランク:无題'),
    ('latest-profile-player-name', '无', '无'),
    ('latest-trade-listed', '上架中', '出品中'),
    ('latest-trade-review', '公示中', '審査中'),
    ('latest-party-platform', '组队平台', 'パーティ検索'),
    ('latest-party-platform-traditional', '組隊平台', 'パーティ検索'),
    ('latest-party-recruiting', "TestPlayer's party is recruiting", 'TestPlayerのパーティがメンバー募集中'),
    ('latest-party-recruiting-mixed', 'TestPlayerのparty is recruiting', 'TestPlayerのパーティがメンバー募集中'),
    ('latest-party-recruiting-rich', '<color=#7e7361>Milk</color>のparty is recruiting', '<color=#7e7361>Milk</color>のパーティがメンバー募集中'),
    ('latest-party-free-text', 'TestPlayer:party is recruiting', 'TestPlayer:party is recruiting'),
    ('latest-guild-funds', '资金榜', '資金ランキング'),
    ('latest-guild-funds-traditional', '資金榜', '資金ランキング'),
    ('latest-guild-rank', '排名', '順位'),
    ('latest-guild-player', '玩家名称', 'プレイヤー名'),
    ('latest-guild-position', '职务', '役職'),
    ('latest-guild-donation', '捐赠额度', '寄付額'),
    ('latest-soul-core', '无主灵魂核心', '主なきソウルコア'),
    ('latest-soul-core-traditional', '無主靈魂核心', '主なきソウルコア'),
    ('latest-guild-members', '公会人数达到60', 'ギルドメンバー数が60に到達'),
    ('latest-guild-members-unit', '公会人数达到80人', 'ギルドメンバー数が80に到達'),
    ('latest-guild-members-rich', '公會人數達到<color=#ffffff>60</color>人', 'ギルドメンバー数が<color=#ffffff>60</color>に到達'),
    ('latest-guild-activity', '上周公会活跃评级达到比较活跃段', '先週、ギルド活動評価がやや活発に到達しました。'),
    ('latest-guild-activity-traditional', '上週公會活躍評級達到比較活躍段', '先週、ギルド活動評価がやや活発に到達しました。'),
    ('latest-guild-time', '每赛程首周周一 6:00', '各日程の第1週・月曜日 6:00'),
    ('latest-guild-time-compact', '每赛程首周周一6:00', '各日程の第1週・月曜日 6:00'),
    ('latest-guild-time-varied', '每賽程首週週一 07:30', '各日程の第1週・月曜日 07:30'),
    ('latest-guild-free-text', 'TestPlayer:公会人数达到60 is my message', 'TestPlayer:公会人数达到60 is my message'),
    ('extra-job-fullwidth', 'Job Restriction：Mage、Mage Class、Priest Class', 'ジョブ制限：マジシャン、マジシャン系、プリースト系'),
    ('extra-job-fullwidth-wrapped', r'Level Req： 50\nJob Restriction：Mage, Mage\nClass, Priest Class', r'必要レベル: 50\nジョブ制限：マジシャン、マジシャン系、プリースト系'),
    ('extra-job-compact', 'JobRestriction: Mage、MageClass、PriestClass', 'ジョブ制限：マジシャン、マジシャン系、プリースト系'),
    ('extra-quest-chapter', '[Main Quest]Chapter 8:  Time to Explore Freely', '[メインクエスト]第8章:  自由探索の時間'),
    ('extra-quest-chapter-rich', '<color=#cc762a>[Main Quest]</color>Chapter 8: Time to Explore Freely', '<color=#cc762a>[メインクエスト]</color>第8章: 自由探索の時間'),
    ('extra-quest-chapter-mixed', '[メインクエスト]Chapter 8: 自由探索の時間', '[メインクエスト]第8章: 自由探索の時間'),
    ('extra-quest-unknown', '[Main Quest]Chapter 8: My Custom Title', '[Main Quest]Chapter 8: My Custom Title'),
    ('extra-quest-chat', 'TestPlayer:[Main Quest]Chapter 8: Time to Explore Freely', 'TestPlayer:[Main Quest]Chapter 8: Time to Explore Freely'),
    ('extra-commission-counter', '[Commission] Defeat Monsters (2/10)', '[依頼] モンスター討伐（2/10）'),
    ('extra-commission-counter-rich', '<color=#ec8c2f>[Commission]</color> Defeat Monsters (2/10)', '<color=#ec8c2f>[依頼]</color> モンスター討伐（2/10）'),
    ('extra-commission-map-objective', 'Geffen Outskirtsでモンスターを討伐：0/20', 'ゲフェン郊外でモンスターを討伐：0/20'),
    ('extra-life-skill-exp-gardener', 'Gardener 経験 +270 (51930/55000)', '園芸師 経験 +270 (51930/55000)'),
    ('extra-life-skill-exp-miner', 'Miner 経験 +30 (10/100)', '採掘師 経験 +30 (10/100)'),
    ('extra-life-skill-exp-chef', '<color=#cccccc>Chef</color> 経験 +20 (3/100)', '<color=#cccccc>調理師</color> 経験 +20 (3/100)'),
    ('live-quest-body-english', r"You've reached the end of the current main Quests. Check out the events and enjoy your adventures in this world!\nCurrent Server Level Cap: Lv. 69\n09/24/2026 05:00:00: Server Level Cap increases to Lv. 79", r'現在のメインクエストはここまでです。イベントもチェックして、この世界での冒険を楽しみましょう！\n現在のサーバーレベル上限：Lv.69\n09/24/2026 05:00:00：サーバーレベル上限がLv.79に上昇'),
    ('live-quest-body-mixed', r"You've reached the end of the current main Quests. Check out the events and enjoy your adventures in this world!\n現在のサーバーレベル上限：Lv.69\n09/24/2026 05:00:00：サーバーレベル上限がLv.79に上昇", r'現在のメインクエストはここまでです。イベントもチェックして、この世界での冒険を楽しみましょう！\n現在のサーバーレベル上限：Lv.69\n09/24/2026 05:00:00：サーバーレベル上限がLv.79に上昇'),
    ('extra-quest-wrapped-prose', r"You've reached the end of the current main Quests. Check out the events\n and enjoy your adventures in this world!", '現在のメインクエストはここまでです。イベントもチェックして、この世界での冒険を楽しみましょう！'),
    ('extra-pet-buff', 'Increases the targetのPhysical DEF and Magic DEF by <color=#cc762a>10%</color>.', 'ターゲットの物理防御力と魔法防御力が<color=#cc762a>10%</color>増加します。'),
    ('extra-card-counter', 'Standard Cards Collected: <color=#cc762a>78/202</color>', '通常カード収集：<color=#cc762a>78/202</color>'),
    ('extra-card-counter-separated', 'Standard Cards Collected: <color=#cc762a>79</color>/203', '通常カード収集：<color=#cc762a>79</color>/203'),
    ('extra-sale-count', 'For Sale: <color=#cc762a>3</color>', '販売中: <color=#cc762a>3</color>'),
    ('live-auction-countdown', '20:45 Ends', '20:45 終了'),
    ('extra-auction-countdown-rich', '<color=#fdab5b>01:20:45</color> Ends', '<color=#fdab5b>01:20:45</color> 終了'),
    ('extra-auction-free-text', 'Test Player Ends', 'Test Player Ends'),
    ('live-login-prefab-support', '客服', 'サポート'),
    ('live-character-prefab-create', '新建', '作成'),
    ('live-map-chat-tail', '<#d5b376><nlink=openplayerInfo/123>TestPlayer</nlink>:</color><color=#FDAB5B><u><link="findpath/10220/281/0/323/1">斐扬树林(281,323)</link></u></color>  50%', '<#d5b376><nlink=openplayerInfo/123>TestPlayer</nlink>:</color><color=#FDAB5B><u><link="findpath/10220/281/0/323/1">フェイヨンの森(281,323)</link></u></color>  50%'),
    ('extra-map-chat-custom', 'Mage: <link="findpath/10220/281/0/323/1">斐扬树林(281,323)</link> My Free Text 斐扬树林', 'Mage: <link="findpath/10220/281/0/323/1">フェイヨンの森(281,323)</link> My Free Text 斐扬树林'),
    ('extra-map-other-link', '<link="openplayerInfo/123">斐扬树林(281,323)</link> my message', '<link="openplayerInfo/123">斐扬树林(281,323)</link> my message'),
    ('extra-map-unknown-route', '<link="findpath/custom">斐扬树林(281,323)</link> my message', '<link="findpath/custom">斐扬树林(281,323)</link> my message'),
    ('live-map-notice-mixed', 'Eddga has spawned on the 斐扬树林 map.', 'エドガがフェイヨンの森マップに出現しました。'),
    ('live-map-notice-partly-translated', 'Eddgaが斐扬树林マップに出現しました。', 'エドガがフェイヨンの森マップに出現しました。'),
    ('extra-map-notice-colored', '<color=#fdab5b>Eddga</color> has spawned on the <color=#fdab5b>斐扬树林</color> map.', '<color=#fdab5b>エドガ</color>が<color=#fdab5b>フェイヨンの森</color>マップに出現しました。'),
    ('live-rare-reward-japanese', 'プレイヤー【TestPlayer】が【Eddga】を撃破し、レア報酬を獲得しました！', 'プレイヤー【TestPlayer】が【エドガ】を撃破し、レア報酬を獲得しました！'),
    ('live-defeat-notice-japanese', 'Moonlight FlowerはTestPlayerに倒されました。', '月夜花はTestPlayerに倒されました。'),
    ('extra-defeat-notice-english', 'Moonlight Flower was defeated by TestPlayer.', '月夜花はTestPlayerに倒されました。'),
    ('extra-defeat-notice-player-name', 'UnlistedBossはEddgaに倒されました。', 'UnlistedBossはEddgaに倒されました。'),
    ('extra-rare-reward-english', 'Congratulations to player 【TestPlayer】 for defeating 【Baphomet】 and earning a Rare reward!', 'プレイヤー【TestPlayer】が【バフォメット】を撃破し、レア報酬を獲得しました！'),
    ('extra-rare-reward-player-name', 'プレイヤー【Eddga】が【UnlistedBoss】を撃破し、レア報酬を獲得しました！', 'プレイヤー【Eddga】が【UnlistedBoss】を撃破し、レア報酬を獲得しました！'),
    ('live-map-treasure-notice', '<color=#fdab5b>TestPlayer</color> disturbed a terrifying BOSS while treasure hunting in <color=#fdab5b>[<color=#FDAB5B><u><link="findpath/10314/67.6/4.25/316.3/1">吉芬北门(67,316)</link></u></color>]</color>! Help Defeat it to receive a <color=#fdab5b>Support Chest</color>!', '<color=#fdab5b>TestPlayer</color>が<color=#fdab5b>[<color=#FDAB5B><u><link="findpath/10314/67.6/4.25/316.3/1">ゲフェン北門(67,316)</link></u></color>]</color>で宝探し中に恐ろしいBOSSを刺激してしまいました！ 討伐に協力して<color=#fdab5b>支援宝箱</color>を手に入れましょう！'),
    ('extra-event-coal', 'During the event, each player can Collect Live Coal up to 10 times.', 'イベント期間中、各プレイヤーは生きた石炭を最大10回集められます。'),
    ('extra-event-coal-colored', 'During the event, each player can Collect Live Coal up to <color=#cc762a>15</color> times.', 'イベント期間中、各プレイヤーは生きた石炭を最大<color=#cc762a>15</color>回集められます。'),
    ('pickup', 'Milk X 7', 'ミルク X 7'),
    ('prerequisite', 'Prerequisite Skill <color=#cc762a>Heal</color>', '前提スキル <color=#cc762a>ヒール</color>'),
    ('live-heal-skill-cn', '治愈术', 'ヒール'),
    ('live-heal-skill-tw', '治癒術', 'ヒール'),
    ('live-heal-prerequisite-cn', 'Prerequisite Skill <color=#cc762a>治愈术 Lv.5 </color>', '前提スキル <color=#cc762a>ヒール Lv.5 </color>'),
    ('live-heal-prerequisite-tw', '前提スキル <color=#cc762a>治癒術 Lv.7 </color>', '前提スキル <color=#cc762a>ヒール Lv.7 </color>'),
    ('screenshot-prerequisite-levels', 'Prerequisite Skill <color=#cc762a>Mana Recharge Lv.10＋十字驅魔攻擊 Lv.10</color>', '前提スキル <color=#cc762a>マナリチャージ Lv.10＋マグヌスエクソシズム Lv.10</color>'),
    ('screenshot-prerequisite-plain', '前提スキル Mana Recharge Lv.10 + 十字驱魔攻击 Lv.10', '前提スキル マナリチャージ Lv.10 + マグヌスエクソシズム Lv.10'),
    ('screenshot-prerequisite-unknown', 'Prerequisite Skill UnlistedSkill Lv.10', '前提スキル UnlistedSkill Lv.10'),
    ('screenshot-countdown', '04 Minute 52 sec後に回復', '04分52秒後に回復'),
    ('screenshot-countdown-unknown', '04 Minute 52 sec by TestPlayer', '04 Minute 52 sec by TestPlayer'),
    ('unknown-pickup', 'PlayerUnlisted X 7', 'PlayerUnlisted X 7'),
    ('unknown-skill', 'Prerequisite Skill <color=#cc762a>UnlistedSkill</color>', '前提スキル <color=#cc762a>UnlistedSkill</color>'),
    ('generic-report', 'Report', '通報'),
    ('generic-tips', 'Tips', 'ヒント'),
    ('screen-price', '价格排序', '価格順'),
    ('screen-serpent-title', '灵蛇守护Lv.1', '蛇霊の加護Lv.1'),
    ('screen-sphinx1', 'Sphinx Dungeon Floor 1', 'スフィンクスダンジョン 1F'),
    ('screen-sphinx2', 'Sphinx Dungeon Floor 2', 'スフィンクスダンジョン 2F'),
    ('screen-map-link', 'TestPlayer:Culvert Floor 2(40,109)', 'TestPlayer:地下水路 2階(40,109)'),
    ('screen-map-link2', 'TestPlayer:Payon Forest(202,263)', 'TestPlayer:フェイヨンの森(202,263)'),
    ('screen-map-link3', 'TestPlayer:Abandoned Village(219,195)', 'TestPlayer:廃村(219,195)'),
    ('screen-map-unknown', 'TestPlayer:Unlisted Map(1,2)', 'TestPlayer:Unlisted Map(1,2)'),
    ('screen-free-chat', 'TestPlayer:I like Payon Forest', 'TestPlayer:I like Payon Forest'),
    ('screen-medals', "This WeekのCompetition Medals: 20000/20000", '今週の競技メダル：20000/20000'),
    ('screen-equipment-type', 'Off-Hand - Shield', '盾/サブ武器 - シールド'),
    ('screen-wand-type', '1H - Wand', '1H - ワンド'),
    ('screen-jobs', 'JobRestriction: Swordsman、KnightClass、CrusaderBranch、Mage、MageClass、Priest Class、Merchant、BlacksmithClass', 'ジョブ制限：ソードマン、ナイト系、クルセイダー系統、マジシャン、マジシャン系、プリースト系、マーチャント、ブラックスミスクラス'),
    ('screen-wand-req', r'Level Req: 50\nJob Restriction: Mage, Mage Class, Priest Class', r'必要レベル: 50\nジョブ制限：マジシャン、マジシャン系、プリースト系'),
    ('screen-job-unknown', 'Job Restriction: UnlistedJob', 'ジョブ制限：UnlistedJob'),
    ('screen-jobs-wrapped', r'Job Restriction: Mage, Mage\nClass, Priest Class', 'ジョブ制限：マジシャン、マジシャン系、プリースト系'),
    ('screen-medals-varied', "This Week's Competition Medals: 37/20000", '今週の競技メダル：37/20000'),
    ('screen-medals-colored', 'This WeekのCompetition Medals: <color=#ff993f>37/20000</color>', '今週の競技メダル：<color=#ff993f>37/20000</color>'),
    ('screen-map-west', 'Western Morroc', 'モロック西部'),
])
for key, values in {
    '10960000042': {'@{1}':'1','@{2}':'2','@{3}':'1','@{4}':'3','@{5}':'4','@{6}':'3','@{7}':'6','@{8}':'9','@{9}':'12','@{10}':'15','@{11}':'18','@{12}':'5'},
    '10110300484': {'${1}':'15','${2}':'5','${3}':'180','${4}':'5'},
}.items():
    source, target = mapping[key]
    for token, value in values.items():
        source, target = source.replace(token, value), target.replace(token, value)
    source, target = data.strip_style_placeholders(source), data.strip_style_placeholders(target)
    rows.append(('screen:' + key, source, target))
    if key == '10110300484':
        rows.append(('screen-pet-mixed', source.replace("Serpent's ", 'Serpentの'), target))
        styled_source, styled_target = mapping[key]
        for token, value in values.items():
            styled_source, styled_target = styled_source.replace(token, value), styled_target.replace(token, value)
        styles = {1:'<u>',2:'</u>',3:'<color=#77ab22>',4:'</color>',5:'<color=#77ab22>',6:'</color>',7:'<color=#cc762a>',8:'',9:'',10:'</color>'}
        for index, tag in styles.items():
            styled_source, styled_target = styled_source.replace('^{%d}' % index, tag), styled_target.replace('^{%d}' % index, tag)
        rows.append(('screen-pet-styled', styled_source.replace("Serpent's ", 'Serpentの'), styled_target))
rows.append(('screen-refine-safe', 'After reaching Refinement +6, failure will not reduce it below +6', '精錬値+6到達後は、失敗しても+6未満には下がりません。'))
rows.extend([
    ('new-price-desc', '价格降序', '価格（高い順）'),
    ('new-price-asc', '價格升序', '価格（安い順）'),
    ('new-lineup', '首发', '初期編成'),
    ('new-substitute', '替补', '控え'),
    ('new-stats-title', '属性总览', 'ステータス一覧'),
    ('new-sold-out', '已售罄', '売り切れ'),
    ('new-egg-count', 'Pet Egg x5', translations['Pet Egg'] + ' x5'),
    ('new-egg-count-varied', 'Pet Egg ×12', translations['Pet Egg'] + ' ×12'),
    ('new-unknown-item', 'Unlisted Item x5', 'Unlisted Item x5'),
    ('new-players', 'Recommended Players:40', '推奨人数：40'),
    ('new-players-wrap', r'Recommended\nPlayers: 80', '推奨人数：80'),
])
for day, jp in zip(('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'), ('月曜日','火曜日','水曜日','木曜日','金曜日','土曜日','日曜日')):
    for gap in ('', ' '):
        rows.append(('new-schedule-' + day + str(len(gap)), 'Opens ' + day + gap + '20:00-21:00', jp + ' 20:00-21:00 開催'))
for name in ('PDEF','MDEF','ASPD','Cast Speed','Crit Resistance','Life%','DMG vs All Job','DMG Reduction vs All Job'):
    for suffix in ('+120', '+2.6', '+36.00%', ' -5'):
        rows.append(('new-stat-' + name + suffix, name + suffix, translations[name] + suffix))
    rows.append(('new-stat-prose-' + name, name + '+5 is my build', name + '+5 is my build'))
for key in ('10800100026','10800100027','12110100010','10960000140','74014','74019','290054','38008','38024','23211','23270','10570100003','10570100051','16059','49017','49031','64000'):
    source, target = mapping[key]
    rows.append(('new-template-' + key, render(source), render(target)))
    if "'s " in source:
        rows.append(('new-mixed-' + key, render(source).replace("'s ", 'の'), render(target)))
        styled = lambda text: re.sub(r'\^\{(\d+)\}', lambda m: '<color=#cc762a>' if int(m[1]) % 2 else '</color>', text)
        rows.append(('new-styled-' + key, render(styled(source)).replace("'s ", 'の'), render(styled(target))))
for role in data.load_language_kv_texts(('103600',)):
    for i, source in enumerate(('Available for purchase at position ' + role + ' or above', '順位' + role + '以上で購入可能', role + '以上で購入可能')):
        rows.append(('live-guild-role-' + role + str(i), source, translations[role] + '以上で購入可能'))
rows.append(('live-build-label', 'Build 1', 'ビルド 1'))
for i, (key, source, target) in enumerate(data.build_world_alias_rows(translations)):
    rows.append(('world-alias-' + str(i), render(source), render(target)))
    if key.startswith(('100800', '106801')):
        rows.append(('world-coordinate-' + str(i), 'TestPlayer:' + render(source) + '(40,109)', 'TestPlayer:' + render(target) + '(40,109)'))
rows.extend([
    ('live-auto-dismantle-mixed', '<color=#6890D2>Earrings</color> X 1を自動解体し、<color=#6890D2>Minted Coin</color> X 50を獲得しました。', '<color=#6890D2>イヤリング</color> X 1を自動解体し、<color=#6890D2>鋳造されたコイン</color> X 50を獲得しました。'),
    ('live-auto-dismantle-english', 'Automatically dismantled <color=#62AF5E>Rod</color> X 1 and obtained <color=#6890D2>Minted Coin</color> X 5.', '<color=#62AF5E>ロッド</color> X 1を自動解体し、<color=#6890D2>鋳造されたコイン</color> X 5を獲得しました。'),
    ('audit-dismantle-manual', 'Successfully dismantled <color=#62AF5E>Ring</color> X 1 and obtained <color=#6890D2>Minted Coin</color> X 5.', '<color=#62AF5E>リング</color> X 1を解体し、<color=#6890D2>鋳造されたコイン</color> X 5を獲得しました。'),
    ('audit-combine-success', 'Combine is successful. Obtained <color=#62AF5E>Ring</color> X 1.', '合成成功。<color=#62AF5E>リング</color> X 1を獲得しました。'),
    ('audit-obtained-count', 'Obtained <color=#6890D2>Minted Coin</color> X 50', '<color=#6890D2>鋳造されたコイン</color> X 50 を獲得'),
    ('rich-pickup-coin', '<color=#9fc3ed>Minted Coin</color> X 50', '<color=#9fc3ed>' + translations['Minted Coin'] + '</color> X 50'),
    ('rich-pickup-scale', '<sprite=2><color=#70ba84>Sharp Scale</color> X 1', '<sprite=2><color=#70ba84>' + translations['Sharp Scale'] + '</color> X 1'),
    ('rich-pickup-unknown', '<color=#9fc3ed>Unlisted Item</color> X 50', '<color=#9fc3ed>Unlisted Item</color> X 50'),
    ('rich-map-coordinate', 'TestPlayer:<link="map:001"><color=#ff993f>斐扬树林(202,263)</color></link>', 'TestPlayer:<link="map:001"><color=#ff993f>' + translations['Payon Forest'] + '(202,263)</color></link>'),
    ('rich-map-unknown', 'TestPlayer:<link="map:001"><color=#ff993f>Unlisted Map(1,2)</color></link>', 'TestPlayer:<link="map:001"><color=#ff993f>Unlisted Map(1,2)</color></link>'),
    ('rich-free-chat', '<color=#55ee55>Milk</color>:I like Payon Forest', '<color=#55ee55>Milk</color>:I like Payon Forest'),
    ('rich-job-wrapper', '<size=22>JobRestriction: Mage、MageClass、PriestClass</size>', '<size=22>ジョブ制限：マジシャン、マジシャン系、プリースト系</size>'),
    ('rich-sibling-colors', '<color=#9fc3ed>Unlisted</color> + <color=#70ba84>Other</color>', '<color=#9fc3ed>Unlisted</color> + <color=#70ba84>Other</color>'),
])
for key, stat, value in (('10800100225', 'INT', '28'), ('10800100226', 'DEX', '16')):
    source, target = mapping[key]
    for token, number in (('${1}', '4'), ('${2}', '1'), ('${3}', '50')):
        source, target = source.replace(token, number), target.replace(token, number)
    for style in ('', '<color=#cc762a>'):
        amount = style + '+' + value + ('</color>' if style else '')
        rows.append(('resonance-current-' + stat + str(len(style)), '♦' + source + '[Current ' + amount + ']', '♦' + target + '【現在 ' + amount + '】'))
for key, skill in (('10110300827', 'Song of Suffering - Organum'), ('10110300829', 'Song of Suffering - Murmur'), ('10110300831', 'Song of Suffering - Baptism')):
    source, target = mapping[key]
    style = lambda text: re.sub(r'\^\{(\d+)\}', lambda m: '<color=#cc762a>' if int(m[1]) % 2 else '</color>', text)
    source, target = render(style(source)), render(style(target))
    for square in (False, True):
        a, b = (source.replace('【', '[').replace('】', ']'), target.replace('【', '[').replace('】', ']')) if square else (source, target)
        rows.append(('resonance-skill-' + key + str(square), '♦' + skill + ':  ' + a, '♦' + translations[skill] + '：' + b))
    # Live resonance uses a full-width colon and nested links, unlike its source table.
    rows.append(('resonance-fullwidth-' + key, skill + '：' + source, translations[skill] + '：' + target))

for key, skill, links in (
    ('10110300827', 'Song of Suffering - Organum', {4: 'skill/11431101'}),
    ('10110300829', 'Song of Suffering - Murmur', {4: 'skill/11431301', 8: 'buff/11431301', 14: 'skill/11431101'}),
    ('10110300831', 'Song of Suffering - Baptism', {8: 'skill/11431701', 12: 'buff/11431701', 16: 'buff/11431301'}),
):
    source, target = mapping[key]
    slots = {}
    for match in re.finditer(r'\^\{(\d+)\}', source):
        index = int(match[1])
        if index in links:
            slots[match[0]] = '<link="' + links[index] + '">'
        elif index - 1 in links:
            slots[match[0]] = '</link>'
        elif index + 1 in links or index % 2:
            slots[match[0]] = '<color=#cc762a>'
        else:
            slots[match[0]] = '</color>'
    slots.update({'@{1}': '1', '@{2}': '3', '${1}': '20'})
    substitute = lambda match: slots[match[0]]
    rows.append(('live-resonance-links:' + key,
                 skill + '：' + data.RUNTIME_TOKEN_RE.sub(substitute, source),
                 translations[skill] + '：' + data.RUNTIME_TOKEN_RE.sub(substitute, target)))

def format_known(source, *values):
    return re.sub(r'\$\{(\d+)\}', lambda m: values[int(m[1]) - 1], translations[source])


for i, (party_body, objective, message, expected_message) in enumerate((
    ("TestPlayer's Party, Party Objective: No Objective,", 'No Objective', 'We look forward to welcoming all Adventurers!', translations['We look forward to welcoming all Adventurers!']),
    ('TestPlayer的队伍，队伍目标：五人挑战-暗黑之地，', '5-Player Challenge - Dark Land', '期待各位冒险者的加入！', translations['We look forward to welcoming all Adventurers!']),
    ('TestPlayer的队伍，队伍目标：五人挑战-蛮荒腹地，', '5-Player Challenge - Savage Hinterlands', '来T   3=2', '来T   3=2'),
    ('TestPlayer的隊伍，隊伍目標：無目標，', 'No Objective', 'Milk is my player name', 'Milk is my player name'),
    ("TestPlayer's Party, Party Objective: Unlisted Objective,", None, "Do not translate player's custom message", "Do not translate player's custom message"),
)):
    party = format_known(data.KNOWN_PARTY_NAME_TEMPLATE, 'TestPlayer')
    expected_body = format_known(data.KNOWN_PARTY_OBJECTIVE_TEMPLATE, party, translations[objective] if objective else 'Unlisted Objective') + expected_message
    for state, color, displayed_name in (('1', '#A2988A', ''), ('0', '#CC762A', 'TestPlayer')):
        sender = '<#d5b376><nlink=openplayerInfo/12345>' + displayed_name + '</nlink>:</color>'
        opening = '<color=' + color + '><u><link="jointeam/67890/' + state + '">'
        closing = '</link></u></color>'
        source = sender + party_body + message + r'[Members: 3/5]\n ' + opening + 'Tap to Join Party' + closing
        target = sender + expected_body + format_known(data.KNOWN_CHAT_CARD_TEMPLATE, '', '3', '5', ' ' + opening + translations['Tap to Join Party'] + closing)
        rows.append(('live-recruitment-' + str(i) + state, source, target))
rows.extend((
    ('live-hunt-instruction', 'Kill Monsters to Earn Rewards', translations['Kill Monsters to Earn Rewards']),
    ('recruit-free-chat', 'TestPlayer:Tap to Join Party is a button label', 'TestPlayer:Tap to Join Party is a button label'),
    ('recruit-other-link', '<#d5b376><nlink=openplayerInfo/12345>TestPlayer</nlink>:</color><link="example/67890">My custom text</link>', '<#d5b376><nlink=openplayerInfo/12345>TestPlayer</nlink>:</color><link="example/67890">My custom text</link>'),
))

# Recovery previously translated these table rows before interpolation. Audit
# their completed render forms across the entire current override map, not just
# the historical hand-maintained ID list.
def render_audit_pair(source, target):
    values = {}
    for match in data.RUNTIME_TOKEN_RE.finditer(source):
        if not match[0].startswith('^{') and match[0] not in values:
            values[match[0]] = str(11 * (len(values) + 1))
    if source == '${1} Ends':
        values['${1}'] = '01:20'
    substitute = lambda m: '' if m[0].startswith('^{') else values[m[0]]
    return data.RUNTIME_TOKEN_RE.sub(substitute, source), data.RUNTIME_TOKEN_RE.sub(substitute, target)


rendered_targets = {}
for source, target in translations.items():
    rendered_source, rendered_target = render_audit_pair(source, target)
    rendered_targets.setdefault(rendered_source, set()).add(rendered_target)
for source, target in mapping.values():
    rendered_source, rendered_target = render_audit_pair(source, target)
    rendered_targets.setdefault(rendered_source, set()).add(rendered_target)
for key, (source, target) in sorted(mapping.items()):
    if data.RUNTIME_TOKEN_RE.search(source) and len(data.RUNTIME_TOKEN_RE.sub('', source).strip()) >= 4:
        rendered_source, rendered_target = render_audit_pair(source, target)
        if len(rendered_targets[rendered_source]) > 1:
            # Removing style slots can collapse distinct IDs or an existing
            # canonical label onto identical text (e.g. [Event]). Verify the
            # context-specific meaning by ID; the exact dictionary is also
            # checked independently by the harness, with canonical precedence.
            rows.append(('id:' + key, source, target))
        else:
            rows.append(('template-history:' + key, rendered_source, rendered_target))

mapped_sources = {source for source, _ in mapping.values()}
for index, (source, target) in enumerate(sorted(translations.items())):
    if source in mapped_sources or not data.RUNTIME_TOKEN_RE.search(source):
        continue
    if len(data.RUNTIME_TOKEN_RE.sub('', source).strip()) < 4:
        continue
    rendered_source, rendered_target = render_audit_pair(source, target)
    if len(rendered_targets[rendered_source]) == 1:
        rows.append(('canonical-template:' + str(index), rendered_source, rendered_target))
    else:
        # Text stripped of style/context may be shared by several IDs. Preserve
        # the full dictionary contract for these without inventing a by-text
        # preference for an inherently ambiguous rendered label.
        rows.append(('canonical-literal:' + str(index), source, target))

for index, (source, target) in enumerate(sorted(data.build_observed_ui_aliases(translations).items())):
    rendered_source, rendered_target = render_audit_pair(source, target)
    rows.append(('latest-alias:' + str(index), rendered_source, rendered_target))

output = pathlib.Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text('\n'.join('\t'.join(row) for row in rows) + '\n', encoding='utf-8')
print('Generated history checks:', len(rows))
