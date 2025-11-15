import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutMuanTokScreen extends StatelessWidget {
  const AboutMuanTokScreen({super.key});

  static const Color kPurple = Color(0xFF7C3AED); // main Lucid purple
  static const Color kPurpleDark = Color(0xFF4C1D95);

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPurple,
      appBar: AppBar(
        backgroundColor: kPurple,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'About',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo (bigger)
                Container(
                  padding: const EdgeInsets.all(10), // less padding → more space for logo
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval( // ensure logo stays perfectly round
                    child: Image.asset(
                      'assets/images/muan_tok_logo.png',
                      width: 150, // bigger logo
                      height: 150,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // 🔹 EXTRA SPACE between logo & title
                const SizedBox(height: 20),

                // Title
                const Text(
                  'Muan Tok',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.6,
                  ),
                ),

                // more space before paragraphs
                const SizedBox(height: 24),

                // Paragraph 1 – TikTok-inspired + concept
                const Text(
                  'Muan Tok is a TikTok-inspired live-shopping and social commerce platform that turns short videos '
                      'and live streams into a fun, interactive marketplace. Instead of only scrolling through content, '
                      'users can discover real products in real time, join live events, and shop directly from creators '
                      'and sellers inside the app. Every card, banner, and screen is designed to feel familiar to video-first '
                      'users while still focusing on clarity, trust, and a smooth buying experience.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),

                // Paragraph 2 – e-commerce, POS, live stream + product cards, roles
                const Text(
                  'At its core, Muan Tok combines an e-commerce platform and POS-style product management with social '
                      'features like following & followers, messaging, and media sharing. Sellers can publish products, manage '
                      'their stock like a mini POS system, and run promotions or event-based discounts. During live streams, '
                      'product cards appear directly on the video as the streamer showcases them, so viewers can tap, view '
                      'details, and purchase without leaving the experience. Any user can grow into a seller, host events, and '
                      'promote their own items, making the platform feel open, creator-friendly, and community-driven.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),

                // Paragraph 3 – delivery tracking, ratings, filters, recommendations
                const Text(
                  'We also focus strongly on transparency and convenience after the user taps “Buy”. Orders come with real-time '
                      'delivery status so buyers can track progress all the way to completion. Once an order is delivered, users can '
                      'rate the products they received, and these ratings accumulate on the product cards. This helps new buyers quickly '
                      'see which items are trusted and which streamers or shops have consistent quality. To make discovery even easier, '
                      'Muan Tok includes flexible filters, smart search, and recommendation logic that highlights products a user might '
                      'be interested in based on categories, events, and engagement. We carefully design every part of the app to feel '
                      'convenient, enjoyable, and friendly so that both buyers and sellers are happy to come back, explore, and have fun.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 32),

                // Developed by – white rounded rectangle card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Developed by',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kPurpleDark,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _DeveloperLinkTile(
                        name: 'Hein Thaw Sitt',
                        url: 'https://www.linkedin.com/in/hein-thaw-sitt-8130822b4/',
                        avatarAsset: 'assets/images/heinthawsitt.jpeg',
                        onTapOpen: _openLink,
                      ),
                      _DeveloperLinkTile(
                        name: 'Htet Aung Thant',
                        url: 'https://www.linkedin.com/in/htet-aung-thant-378960218/?locale=en',
                        avatarAsset: 'assets/images/htetaungthat.png',
                        onTapOpen: _openLink,
                      ),
                      _DeveloperLinkTile(
                        name: 'Pai Zay Oo',
                        url: 'https://www.linkedin.com/in/paizay-oo-420a0429a/',
                        avatarAsset: 'assets/images/paizayoo.png',
                        onTapOpen: _openLink,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeveloperLinkTile extends StatelessWidget {
  final String name;
  final String url;
  final String avatarAsset;
  final Future<void> Function(String url) onTapOpen;

  const _DeveloperLinkTile({
    required this.name,
    required this.url,
    required this.avatarAsset,
    required this.onTapOpen,
  });

  @override
  Widget build(BuildContext context) {
    const devPurple = Color(0xFF4C1D95);

    return InkWell(
      onTap: () => onTapOpen(url),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFEDE9FE),
              backgroundImage: AssetImage(avatarAsset),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 15.5,
                  color: devPurple,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const Icon(
              Icons.open_in_new,
              size: 18,
              color: devPurple,
            ),
          ],
        ),
      ),
    );
  }
}