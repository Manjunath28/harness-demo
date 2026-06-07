const request = require("supertest");
const app = require("./server");

describe("Application Endpoints", () => {
  describe("GET /", () => {
    it("should return Hello World JSON", async () => {
      const res = await request(app).get("/");
      expect(res.statusCode).toBe(200);
      expect(res.body.message).toBe("Hello World");
      expect(res.body.service).toBe("harness-cicd-sto-app");
    });
  });

  describe("GET /health", () => {
    it("should return healthy status", async () => {
      const res = await request(app).get("/health");
      expect(res.statusCode).toBe(200);
      expect(res.body.status).toBe("healthy");
      expect(res.body).toHaveProperty("timestamp");
      expect(res.body).toHaveProperty("uptime");
    });
  });

  describe("Unknown route", () => {
    it("should return 404 for unknown routes", async () => {
      const res = await request(app).get("/unknown");
      expect(res.statusCode).toBe(404);
    });
  });
});
