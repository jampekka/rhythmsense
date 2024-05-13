self.addEventListener("activate", () => {
	clients.claim();
});

self.addEventListener("install", (event) => {
	event.waitUntil(async function() {
		let cache = await caches.open("dontcare");
		await cache.addAll(["/", "index.html"]);
	});
});

async function handleFetch(event) {
	try {
		let response = await fetch(event.request);
		let cache = await caches.open("dontcare");
		cache.put(event.request, response.clone());
		console.log("From network");
		return response;
   	} catch (error) {
		console.log("From cache");
		return caches.match(event.request);
	}
}

self.addEventListener('fetch', function (event) {
	event.respondWith(handleFetch(event));
});

