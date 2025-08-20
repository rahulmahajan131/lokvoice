/**
 * Cloud Function: getDistrictNews
 * Caches news results in Firestore for 24h (state+district key)
 */

const {onRequest} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const admin = require("firebase-admin");
const axios = require("axios");

setGlobalOptions({
  region: "asia-south1",
  timeoutSeconds: 10,
  memory: "256MiB",
});

admin.initializeApp();
const db = admin.firestore();

const NEWS_API_KEY = "pub_3f7f7aae73f042279ddf1faa6901f1d4";
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

const stateLanguages = {
  "Andhra Pradesh": "te",
  "Arunachal Pradesh": "en",
  "Assam": "as",
  "Bihar": "hi",
  "Chhattisgarh": "hi",
  "Delhi": "hi",
  "Goa": "en",
  "Gujarat": "gu",
  "Haryana": "hi",
  "Himachal Pradesh": "hi",
  "Jammu and Kashmir": "en",
  "Jharkhand": "hi",
  "Karnataka": "kn",
  "Kerala": "ml",
  "Madhya Pradesh": "hi",
  "Maharashtra": "mr",
  "Manipur": "en",
  "Meghalaya": "en",
  "Mizoram": "en",
  "Nagaland": "en",
  "Odisha": "or",
  "Punjab": "pa",
  "Rajasthan": "hi",
  "Sikkim": "en",
  "Tamil Nadu": "ta",
  "Telangana": "te",
  "Tripura": "en",
  "Uttar Pradesh": "hi",
  "Uttarakhand": "hi",
  "West Bengal": "bn",
};

exports.getDistrictNews = onRequest(async (req, res) => {
  try {
    const state = (req.query.state || "").trim();
    const district = (req.query.district || "").trim();

    if (!state || !district) {
      return res.status(400).json({
        error: "Missing 'state' or 'district' param.",
      });
    }

    const cacheId = `${state.toLowerCase()}_${district.toLowerCase()}`
        .replace(/ /g, "_");
    const docRef = db.collection("newsCache").doc(cacheId);
    const docSnap = await docRef.get();
    const now = Date.now();

    if (docSnap.exists) {
      const data = docSnap.data();
      if (now - data.timestamp < ONE_DAY_MS) {
        return res.status(200).json(data.articles);
      }
    }

    const lang = stateLanguages[state] || "en";

    const response = await axios.get("https://newsdata.io/api/1/news", {
      params: {
        apikey: NEWS_API_KEY,
        language: lang,
        country: "in",
        q: district,
      },
    });

    if (
      response.status !== 200 ||
      response.data.status !== "success" ||
      !response.data.results
    ) {
      return res.status(502).json({
        error: "News provider error.",
      });
    }

    const articles = response.data.results;

    await docRef.set({
      timestamp: now,
      articles,
    });

    return res.status(200).json(articles);
  } catch (err) {
    console.error("Function error:", err);
    return res.status(500).json({
      error: "Internal server error.",
    });
  }
});
