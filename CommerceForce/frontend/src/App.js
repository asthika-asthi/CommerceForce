import React, { useEffect, useState } from "react";

function App() {
  const [message, setMessage] = useState("Loading...");

  const API_URL = process.env.REACT_APP_API_URL || "http://localhost:8080";// || "http://backend:8080/api/health"; const API_URL = "https://api.yourapp.com";
  useEffect(() => {
    fetch(API_URL)
      .then(res => res.json())
      .then(data => setMessage(data.message))
      .catch(() => setMessage("Error connecting to backend"));
  }, []);

  return (
    <div style={{ textAlign: "center", marginTop: "50px" }}>
      <h1>Frontend Running</h1>
      <h2>{message}</h2>
    </div>
  );
}

export default App;

    // #fetch("http://localhost:8000/api/health")