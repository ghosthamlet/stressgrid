import * as filesize from 'filesize';
import * as _ from 'lodash';
import { inject, observer } from 'mobx-react';
import * as React from 'react';

import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'

import { GeneratorsStore } from './stores/GeneratorsStore'
import { ReportsStore } from './stores/ReportsStore'
import { RunsStore } from './stores/RunsStore'
import { Ws } from './Ws';

const defaultScript = `0..100 |> Enum.each(fn _ ->
  get("/")
  delay(100, 0.1)
end)`;

interface IAppProps {
  generatorsStore?: GeneratorsStore;
  runsStore?: RunsStore;
  reportsStore?: ReportsStore;
  ws?: Ws;
}

interface IAppState {
  error?: string;
}

@inject('generatorsStore')
@inject('runsStore')
@inject('reportsStore')
@inject('ws')
@observer
class App extends React.Component<IAppProps, IAppState> {
  private nameInputRef: React.RefObject<HTMLInputElement> = React.createRef();
  private desiredSizeInputRef: React.RefObject<HTMLInputElement> = React.createRef();

  private scriptTextRef: React.RefObject<HTMLTextAreaElement> = React.createRef();
  private paramsTextRef: React.RefObject<HTMLTextAreaElement> = React.createRef();

  private hostInputRef: React.RefObject<HTMLInputElement> = React.createRef();
  private portInputRef: React.RefObject<HTMLInputElement> = React.createRef();

  private rampupSecsInputRef: React.RefObject<HTMLInputElement> = React.createRef();
  private sustainSecsInputRef: React.RefObject<HTMLInputElement> = React.createRef();
  private rampdownSecsInputRef: React.RefObject<HTMLInputElement> = React.createRef();

  constructor(props: IAppProps) {
    super(props);
    this.state = {};
  }

  public render() {
    const { generatorsStore, runsStore, reportsStore } = this.props;
    return (
      <div className="fluid-container p-4">
        <div className="row">
          <h2>Stressgrid Management</h2>
        </div>
        <div className="row">
          <div className="col-4 p-4">
            <h3>Plan</h3>
            <form className="bg-light rounded p-4">
              {this.state.error && <div className="alert alert-danger" role="alert">
                {this.state.error}
              </div>}
              <fieldset>
                <div className="form-group">
                  <label htmlFor="name">Plan name</label>
                  <input className="form-control" id="name" type="text" ref={this.nameInputRef} defaultValue="10K" />
                </div>
                <div className="row">
                  <div className="col">
                    <div className="form-group">
                      <label htmlFor="desizedSize">Desired number of devices</label>
                      <input className="form-control" id="desizedSize" type="text" ref={this.desiredSizeInputRef} onChange={this.updateDesiredSize} defaultValue="10000" />
                    </div>
                  </div>
                  <div className="col">
                    <div className="form-group">
                      <label htmlFor="size">Effective number of devices</label>
                      <input className="form-control" id="size" type="text" value={_.defaultTo(generatorsStore ? generatorsStore.size : NaN, 0)} readOnly={true} />
                      <small id="passwordHelpBlock" className="form-text text-muted">Multiples of ramp step size: {generatorsStore ? generatorsStore.rampStepSize : NaN}</small>
                    </div>
                  </div>
                </div>
                <div className="form-group">
                  <label htmlFor="script">Script</label>
                  <textarea className="form-control" id="script" rows={8} ref={this.scriptTextRef} defaultValue={defaultScript} />
                </div>
                <div className="form-group">
                  <label htmlFor="params">Params</label>
                  <textarea className="form-control" id="params" rows={1} ref={this.paramsTextRef} defaultValue='{ }' />
                </div>
                <div className="row">
                  <div className="col">
                    <div className="form-group">
                      <label htmlFor="host">Target host</label>
                      <input className="form-control" id="host" type="text" ref={this.hostInputRef} defaultValue="localhost" />
                    </div>
                  </div>
                  <div className="col">
                    <div className="form-group">
                      <label htmlFor="port">Target port</label>
                      <input className="form-control" id="port" type="text" ref={this.portInputRef} defaultValue="5000" />
                    </div>
                  </div>
                </div>
                <div className="row">
                  <div className="col">
                    <div className="form-group">
                      <label htmlFor="rampupSecs">Rampup (seconds)</label>
                      <input className="form-control" id="rampupSecs" type="text" ref={this.rampupSecsInputRef} defaultValue="900" />
                    </div>
                  </div>
                  <div className="col">
                    <div className="form-group">
                      <label htmlFor="sustainSecs">Sustain (seconds)</label>
                      <input className="form-control" id="sustainSecs" type="text" ref={this.sustainSecsInputRef} defaultValue="900" />
                    </div>
                  </div>
                  <div className="col">
                    <div className="form-group">
                      <label htmlFor="rampdownSecs">Rampdown (seconds)</label>
                      <input className="form-control" id="rampdownSecs" type="text" ref={this.rampdownSecsInputRef} defaultValue="900" />
                    </div>
                  </div>
                </div>
                <button className="btn btn-primary" onClick={this.runPlan}>Run</button>
              </fieldset>
            </form>
          </div>
          <div className="col-8 p-4">
            <h3>Runs</h3>
            {runsStore && <table className="table">
              <thead>
                <tr>
                  <th scope="col" style={{ width: "30%" }}>ID</th>
                  <th scope="col" style={{ width: "20%" }}>Plan</th>
                  <th scope="col" style={{ width: "20%" }}>State</th>
                  <th scope="col" style={{ width: "15%" }}>Remaning</th>
                  <th scope="col" style={{ width: "15%" }}>Control</th>
                </tr>
              </thead>
              <tbody>
                {_.map(runsStore.runs, (run, id) => (
                  <tr key={id}>
                    <td><FontAwesomeIcon icon="spinner" spin={true} />&nbsp;{id}</td>
                    <td>{run.name}</td>
                    <td>{_.defaultTo(run.state, '???')}</td>
                    <td>{_.defaultTo(run.remainingMs, 0) / 1000} seconds</td>
                    <td><button data-id={id} className='btn btn-danger btn-sm' onClick={this.abortRun}>Abort</button></td>
                  </tr>
                ))}
              </tbody>
            </table>}
            <h3>Reports</h3>
            {reportsStore && <table className="table">
              <thead>
                <tr>
                  <th scope="col" style={{ width: "30%" }}>ID</th>
                  <th scope="col" style={{ width: "20%" }}>Plan</th>
                  <th scope="col" style={{ width: "20%" }}>Max CPU</th>
                  <th scope="col" style={{ width: "30%" }}>Results</th>
                </tr>
              </thead>
              <tbody>
                {_.reverse(_.map(reportsStore.reports, (report, id) => {
                  const maxCpu = _.defaultTo(report.maxCpu, 0);
                  return <tr key={id}>
                    <td><FontAwesomeIcon style={{ color: maxCpu > .8 ? "red" : "green" }} icon="flag" />&nbsp;{id}</td>
                    <td>{report.name}</td>
                    <td>{Math.trunc(maxCpu * 100)} %</td>
                    <td>{report.csvUrl ? <a href={report.csvUrl} className='btn btn-outline-info btn-sm mr-1' target='_blank'>CSV</a> : null}
                      {report.cwUrl ? <a href={report.cwUrl} className='btn btn-outline-info btn-sm mr-1' target='_blank'>CloudWatch</a> : null}
                      <button data-id={id} className='btn btn-outline-danger btn-sm mr-1' onClick={this.removeReport}>Clear</button></td>
                  </tr>
                }))}
              </tbody>
            </table>}
            <h3>Generators</h3>
            {generatorsStore && <table className="table">
              <thead>
                <tr>
                  <th scope="col" style={{ width: "30%" }}>Name</th>
                  <th scope="col" style={{ width: "20%" }}>Devices</th>
                  <th scope="col" style={{ width: "10%" }}>CPU</th>
                  <th scope="col" style={{ width: "20%" }}>Receive</th>
                  <th scope="col" style={{ width: "20%" }}>Transmit</th>
                </tr>
              </thead>
              <tbody>
                {_.map(generatorsStore.generators, (g, id) => {
                  const cpu = _.defaultTo(g.cpu, 0);
                  return <tr key={id}>
                    <th scope="row"><FontAwesomeIcon style={{ color: cpu > .8 ? "red" : "green" }} icon="cog" spin={_.defaultTo(g.activeCount, 0) > 0} />&nbsp;{id}</th>
                    <td>{_.defaultTo(g.activeCount, 0)}</td>
                    <td>{Math.trunc(cpu * 100)} %</td>
                    <td>{filesize(_.defaultTo(g.networkRx, 0))}/sec</td>
                    <td>{filesize(_.defaultTo(g.networkTx, 0))}/sec</td>
                  </tr>
                })}
                <tr>
                  <th scope="row">All</th>
                  <td>{_.sum(_.map(generatorsStore.generators, g => _.defaultTo(g.activeCount, 0)))}</td>
                  <td>{_.defaultTo(Math.trunc((_.sum(_.map(generatorsStore.generators, g => _.defaultTo(g.cpu, 0))) / _.size(generatorsStore.generators)) * 100), 0)} %</td>
                  <td>{filesize(_.sum(_.map(generatorsStore.generators, g => _.defaultTo(g.networkRx, 0))))}/sec</td>
                  <td>{filesize(_.sum(_.map(generatorsStore.generators, g => _.defaultTo(g.networkTx, 0))))}/sec</td>
                </tr>
              </tbody>
            </table>}
          </div>
        </div>
      </div>
    );
  }

  public componentDidMount() {
    this.updateDesiredSize();
  }

  private updateDesiredSize = () => {
    const desiredSizeInput = this.desiredSizeInputRef.current;
    if (desiredSizeInput && this.props.generatorsStore) {
      this.props.generatorsStore.desiredSize = parseInt(desiredSizeInput.value, 10);
    }
  }

  private runPlan = (event: React.SyntheticEvent<HTMLButtonElement>) => {
    const { generatorsStore, ws } = this.props;
    const nameInput = this.nameInputRef.current;
    const scriptText = this.scriptTextRef.current;
    const paramsText = this.paramsTextRef.current;
    const hostInput = this.hostInputRef.current;
    const portInput = this.portInputRef.current;
    const rampupSecsInput = this.rampupSecsInputRef.current;
    const sustainSecsInput = this.sustainSecsInputRef.current;
    const rampdownSecsInput = this.rampdownSecsInputRef.current;

    if (ws && generatorsStore && nameInput && hostInput && portInput && scriptText && paramsText && rampupSecsInput && sustainSecsInput && rampdownSecsInput) {
      this.setState({ error: undefined });
      try {
        const name = nameInput.value;
        const port = parseInt(portInput.value, 10);
        const size = generatorsStore.size;
        const rampSteps = generatorsStore.rampSteps;
        const rampdownStepMs = (parseInt(rampdownSecsInput.value, 10) * 1000) / rampSteps;
        const rampupStepMs = (parseInt(rampupSecsInput.value, 10) * 1000) / rampSteps;
        const sustainMs = (parseInt(sustainSecsInput.value, 10) * 1000);
        if (_.isEmpty(name)) { throw new Error('Name is invalid'); }
        if (isNaN(port) || port <= 0) { throw new Error('Port is invalid'); }
        if (isNaN(size) || size <= 0) { throw new Error('Effective size is invalid'); }
        if (isNaN(rampSteps) || rampSteps <= 0) { throw new Error('Ramp steps is invalid'); }
        if (isNaN(rampdownStepMs) || rampdownStepMs <= 0) { throw new Error('Rampdown duration is invalid'); }
        if (isNaN(rampupStepMs) || rampupStepMs <= 0) { throw new Error('Ramup duration is invalid'); }
        if (isNaN(sustainMs) || sustainMs <= 0) { throw new Error('Sustain duration is invalid'); }
        ws.run({
          addresses: [{
            host: hostInput.value,
            port
          }],
          blocks: [{
            params: JSON.parse(paramsText.value),
            script: scriptText.value,
            size
          }],
          name,
          opts: {
            ramp_steps: rampSteps,
            rampdown_step_ms: rampdownStepMs,
            rampup_step_ms: rampupStepMs,
            sustain_ms: sustainMs
          }
        });
      }
      catch (e) {
        this.setState({ error: e.toString() });
      }
    }
    event.preventDefault();
  }

  private abortRun = (event: React.SyntheticEvent<HTMLButtonElement>) => {
    const { ws } = this.props;
    const id = event.currentTarget.dataset.id
    if (ws && id) {
      ws.abortRun(id);
    }
  }

  private removeReport = (event: React.SyntheticEvent<HTMLButtonElement>) => {
    const { ws } = this.props;
    const id = event.currentTarget.dataset.id
    if (ws && id) {
      ws.removeReport(id);
    }
  }
}

export default App;
