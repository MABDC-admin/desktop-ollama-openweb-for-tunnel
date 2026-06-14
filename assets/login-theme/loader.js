(() => {
	'use strict';

	const VIDEO_ID = 'openwebui-auth-background-video';
	const VIDEO_SRC = '/static/turn_into_a_video_animation.mp4';

	function isAuthRoute() {
		return window.location.pathname === '/auth' || Boolean(document.getElementById('auth-page'));
	}

	function ensureAuthVideo() {
		const existing = document.getElementById(VIDEO_ID);

		if (!isAuthRoute()) {
			existing?.remove();
			document.documentElement.classList.remove('openwebui-video-auth');
			return;
		}

		document.documentElement.classList.add('openwebui-video-auth');

		if (existing) {
			return;
		}

		const video = document.createElement('video');
		video.id = VIDEO_ID;
		video.src = VIDEO_SRC;
		video.muted = true;
		video.defaultMuted = true;
		video.autoplay = true;
		video.loop = true;
		video.playsInline = true;
		video.preload = 'auto';
		video.setAttribute('aria-hidden', 'true');
		video.setAttribute('tabindex', '-1');
		video.disablePictureInPicture = true;
		video.controls = false;

		document.body.prepend(video);

		const play = () => {
			video.play().catch(() => {
				// Browsers may delay autoplay until the first paint; retry on the next user gesture.
			});
		};

		play();
		window.addEventListener('focus', play, { passive: true });
		document.addEventListener('visibilitychange', () => {
			if (!document.hidden) {
				play();
			}
		});
	}

	window.addEventListener('DOMContentLoaded', ensureAuthVideo, { once: true });
	window.addEventListener('popstate', () => requestAnimationFrame(ensureAuthVideo), { passive: true });

	const observer = new MutationObserver(() => requestAnimationFrame(ensureAuthVideo));
	observer.observe(document.documentElement, { childList: true, subtree: true });
})();
