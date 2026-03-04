import 'package:flutter/material.dart';

class PressureUlcerInfoTab extends StatelessWidget {
  const PressureUlcerInfoTab({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 32 + bottomInset + 24),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 14, left: 24, right: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF6DC16A)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    _PressureUlcerInfoHeader(),
                    _PressureUlcerInfoBody(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PressureUlcerInfoHeader extends StatelessWidget {
  const _PressureUlcerInfoHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF6DC16A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      child: const Text(
        '욕창 단계별 상세 특징',
        style: TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PressureUlcerInfoBody extends StatelessWidget {
  const _PressureUlcerInfoBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        StageRow(
          title: '1단계(지속성 발적)',
          description:
              '피부 파괴는 없으나 붉거나 보라색으로 변하며,눌러도 창백해지지 않는 상태입니다. 주변 피부보다 따뜻하거나 단단하며, 통증이 있을 수 있습니다.',
          diagramAsset: 'assets/images/stage1_diagram.png',
        ),
        StageRow(
          title: '2단계(부분층 피부 손상)',
          description:
              '표피와 진피 일부가 파열된 상태로 물집(수포)이 생기거나 피부가 벗겨집니다. 얕은 궤양 형태이며 분홍색이나 붉은색을 띱니다.',
          diagramAsset: 'assets/images/stage2_diagram.png',
        ),
        StageRow(
          title: '3단계 (전층 피부 손상)',
          description:
              '피부 전층이 파괴되어 피하지방 조직까지 노출됩니다. 둥글게 파인 형태를 띠며, 괴사 조직과 심한 악취를 동반한 삼출물이 나타날 수 있습니다.',
          diagramAsset: 'assets/images/stage3_diagram.png',
        ),
        StageRow(
          title: '4단계 (광범위한 조직 손상)',
          description:
              '피부 전층뿐만 아니라 근육, 힘줄, 뼈까지 노출될 정도로 깊은 손상이 발생합니다. 괴사 조직 제거 및 봉합 등 적극적인 수술적 치료가 필요합니다.',
          diagramAsset: 'assets/images/stage4_diagram.png',
          showBottomBorder: false,
        ),
      ],
    );
  }
}

class StageRow extends StatelessWidget {
  final String title;
  final String description;
  final String diagramAsset;
  final bool showBottomBorder;

  const StageRow({
    super.key,
    required this.title,
    required this.description,
    required this.diagramAsset,
    this.showBottomBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: showBottomBorder
            ? const Border(
                bottom: BorderSide(color: Color(0xFF6DC16A), width: 1),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                SizedBox(height: 130, child: Image.asset(diagramAsset)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
