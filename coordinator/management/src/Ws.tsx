import * as _ from 'lodash';

import generatorsStore from './stores/GeneratorsStore'
import reportsStore from './stores/ReportsStore'
import runsStore from './stores/RunsStore'

import ReconnectingWebSocket from 'reconnecting-websocket';

interface IGeneratorInfo {
  id: string
  cpu?: number;
  network_rx?: number;
  network_tx?: number;
  active_count?: number;
}

interface IRunInfo {
  id: string;
  name?: string;
  state?: string;
  remaining_ms?: number;
}

interface IResultInfo {
  csv_url?: string;
  cw_url?: string;
}

interface IReportInfo {
  id: string;
  name: string;
  max_cpu?: number;
  max_network_rx?: number;
  max_network_tx?: number;
  result: IResultInfo;
}

interface IInit {
  runs: IRunInfo[];
  generators: IGeneratorInfo[];
  reports: IReportInfo[];
}

interface INotify {
  generator_changed?: IGeneratorInfo;
  generator_removed?: { id: string };
  run_changed?: IRunInfo;
  run_removed?: { id: string };
  report_added?: IReportInfo;
  report_removed?: { id: string };
}

interface IBlock {
  script?: string;
  params?: object;
  size?: number;
}

interface IAddress {
  host: string;
  port?: number;
  protocol?: string;
}

interface IOpts {
  ramp_steps?: number;
  rampup_step_ms?: number;
  sustain_ms?: number;
  rampdown_step_ms?: number;
}

interface IRunPlan {
  name: string;
  blocks: IBlock[];
  addresses: IAddress[];
  opts: IOpts;
  script?: string;
}

interface IAbortRun {
  id: string;
}

interface IRemoveReport {
  id: string;
}

interface IMessage {
  init?: IInit;
  notify?: INotify;
  run_plan?: IRunPlan;
  abort_run?: IAbortRun;
  remove_report?: IRemoveReport;
}

export class Ws {
  private ws: ReconnectingWebSocket;

  public connect(wsUrl: string) {
    this.ws = new ReconnectingWebSocket(wsUrl);
    this.ws.onmessage = (e) => {
      _.each(JSON.parse(e.data), (message: IMessage) => {
        this.handle(message);
      });
    }
  }

  public run(runPlan: IRunPlan) {
    this.send([{
      run_plan: runPlan
    }]);
  }

  public abortRun(id: string) {
    this.send([{
      abort_run: {
        id
      }
    }]);
  }

  public removeReport(id: string) {
    this.send([{
      remove_report: {
        id
      }
    }]);
  }

  private send(messages: IMessage[]) {
    this.ws.send(JSON.stringify(messages));
  }

  private handle(message: IMessage) {
    const { init, notify } = message;
    if (init) {
      generatorsStore.clear();
      runsStore.clear();
      reportsStore.clear();

      _.forEach(init.generators, g => generatorsStore.updateGenerator(g.id, { cpu: g.cpu, networkRx: g.network_rx, networkTx: g.network_tx, activeCount: g.active_count }));
      _.forEach(init.runs, p => runsStore.updateRun(p.id, { name: p.name, state: p.state, remainingMs: p.remaining_ms }));
      _.forEach(init.reports, r => reportsStore.addReport(r.id, { name: r.name, maxCpu: r.max_cpu, maxNetworkRx: r.max_network_rx, maxNetworkTx: r.max_network_tx, csvUrl: r.result.csv_url, cwUrl: r.result.cw_url }));
    }
    if (notify) {
      if (notify.generator_changed) {
        const g = notify.generator_changed;
        generatorsStore.updateGenerator(g.id, { cpu: g.cpu, networkRx: g.network_rx, networkTx: g.network_tx, activeCount: g.active_count });
      }
      if (notify.generator_removed) {
        generatorsStore.deleteGenerator(notify.generator_removed.id);
      }
      if (notify.run_changed) {
        const p = notify.run_changed;
        runsStore.updateRun(p.id, { name: p.name, state: p.state, remainingMs: p.remaining_ms });
      }
      if (notify.run_removed) {
        runsStore.deleteRun(notify.run_removed.id);
      }
      if (notify.report_added) {
        const r = notify.report_added;
        reportsStore.addReport(r.id, { name: r.name, maxCpu: r.max_cpu, maxNetworkRx: r.max_network_rx, maxNetworkTx: r.max_network_tx, csvUrl: r.result.csv_url, cwUrl: r.result.cw_url });
      }
      if (notify.report_removed) {
        reportsStore.deleteReport(notify.report_removed.id);
      }
    }
  }
}

const ws = new Ws();
export default ws;