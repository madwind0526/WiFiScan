import 'package:flutter/material.dart';
import 'package:wifi_scan/features/dashboard/domain/network_overview.dart';

class SecurityDashboardPage extends StatefulWidget {
  const SecurityDashboardPage({super.key});

  @override
  State<SecurityDashboardPage> createState() => _SecurityDashboardPageState();
}

class _SecurityDashboardPageState extends State<SecurityDashboardPage> {
  final NetworkOverview _overview = const NetworkOverview.empty();

  void _startScan() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('네트워크 탐색 기능은 다음 단계에서 연결됩니다.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('와이파이 보안 점검')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _StatusHeader(lastScannedAt: _overview.lastScannedAt),
                const SizedBox(height: 16),
                _MetricGrid(overview: _overview),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.radar),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('현재 네트워크 검색 시작'),
                  ),
                ),
                const SizedBox(height: 28),
                const _SectionTitle(
                  title: '연결 장비',
                  description: '휴대폰, 컴퓨터, 가전, IoT 장비를 한곳에서 확인합니다.',
                ),
                const SizedBox(height: 12),
                const _EmptyPanel(
                  icon: Icons.devices_other,
                  title: '확인된 장비가 없습니다.',
                  description: '첫 검색이 완료되면 장비와 마지막 확인 시각이 표시됩니다.',
                ),
                const SizedBox(height: 28),
                const _SectionTitle(
                  title: '보안 경고',
                  description: '발견 근거와 신뢰도를 확인한 뒤 안전한 대응을 선택합니다.',
                ),
                const SizedBox(height: 12),
                const _EmptyPanel(
                  icon: Icons.verified_user_outlined,
                  title: '분석된 경고가 없습니다.',
                  description: '아직 네트워크를 검색하지 않았으므로 안전 판정 전입니다.',
                ),
                const SizedBox(height: 28),
                const _SafetyNotice(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.lastScannedAt});

  final DateTime? lastScannedAt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '현재 네트워크를 아직 점검하지 않았습니다.',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('탐지되지 않은 장비가 있을 수 있으므로 검색 결과와 탐지 범위를 함께 확인하세요.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.overview});

  final NetworkOverview overview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth < 520
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              width: itemWidth,
              label: '확인된 장비',
              value: overview.devices.length.toString(),
              icon: Icons.devices,
            ),
            _MetricCard(
              width: itemWidth,
              label: '미확인 장비',
              value: overview.unconfirmedDeviceCount.toString(),
              icon: Icons.device_unknown,
            ),
            _MetricCard(
              width: itemWidth,
              label: '주의 경고',
              value: overview.warningCount.toString(),
              icon: Icons.warning_amber,
            ),
            _MetricCard(
              width: itemWidth,
              label: '긴급 경고',
              value: overview.criticalCount.toString(),
              icon: Icons.gpp_bad_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
              const SizedBox(width: 12),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(description),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.admin_panel_settings_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'WifiScan은 관리 권한이 있는 네트워크만 비침투 방식으로 점검합니다. '
                '패치나 설정 변경은 공식 관리 경로와 사용자의 명시적 승인이 있을 때만 진행합니다.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
