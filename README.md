**ABAP File Uploader (JSON to Database Table)**
This project provides a lightweight, browser-based solution to upload JSON data directly into SAP on-premise database tables. It uses an ADF (ABAP Development Framework) approach with a custom SICF handler and a SAPUI5 frontend.

🚀 **Features**
**Dynamic Target Tables:** Specify any flat ABAP dictionary table at runtime.

**Upload Modes:** Support for Append (add to existing data) or Replace (clear and refill).

**Modern UI:** Built with SAPUI5 for a clean, Fiori-like user experience.

**Raw Data Processing:** Uses high-performance JSON deserialization (/UI2/CL_JSON).

🛠️ **Installation & Setup**
**Step 1:** Create the Handler Class
Create a new class (e.g., ZCL_FILE_UPLOADER) in transaction SE24.

Go to the Interfaces tab and add IF_HTTP_EXTENSION.

Implement the method IF_HTTP_EXTENSION~HANDLE_REQUEST.

Copy the provided ABAP code into your class methods.

Activate the class.

**Step 2:** Configure the SICF Service
To expose the tool to the web:

Go to Transaction SICF.

Navigate to default_host > sap > bc (or your preferred path).

Create New Element (Service). Give it a name like z_upload.

In the Handler List tab, enter your class name: ZCL_FILE_UPLOADER.

Save and Activate the service (Right-click > Activate Service).

📖 **How to Use**
Test the Service: In SICF, right-click your service and select Test Service. This will open your default browser.

**Enter Table Name:** Type the target SAP table name (e.g., ZMY_TABLE).

**Select Options:** Choose whether to Append or Replace existing data.

**Upload:** Select your .json file and click Upload File.

⚠️ **Prerequisites**
The target table must be active in the ABAP Dictionary (SE11).

The JSON field names must exactly match the ABAP field names (Case-sensitive depending on your deserialization settings).
Note : demo JSON.
[
  {
    "MANDT": "040",
    "JOBID": "0000000001",
    "EMNAM": "STEVE ROGERS",
    "EDESG": "CAP",
    "ESLAF": "150.35",
    "ESALL": "150000.00",
    "ECUKY": "USD",
    "EFLAG": "X"
  },
  {
    "MANDT": "040",
    "JOBID": "0000000002",
    "EMNAM": "ANTHONY EDWARD STARK",
    "EDESG": "CAP",
    "ESLAF": "150000.00",
    "ESALL": "450000.00",
    "ECUKY": "USD",
    "EFLAG": ""
  },
  {
    "MANDT": "040",
    "JOBID": "0000000003",
    "EMNAM": "THOR",
    "EDESG": "VC",
    "ESLAF": "23333.00",
    "ESALL": "2333.00",
    "ECUKY": "USD",
    "EFLAG": "X"
  },
  {
    "MANDT": "040",
    "JOBID": "0000000004",
    "EMNAM": "NATASHA",
    "EDESG": "MEMBER",
    "ESLAF": "0.00",
    "ESALL": "150.00",
    "ECUKY": "USD",
    "EFLAG": ""
  }
]
